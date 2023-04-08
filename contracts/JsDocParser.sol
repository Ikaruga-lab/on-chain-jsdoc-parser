// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import './interfaces/IJsDocParser.sol';
import './Utf8.sol';

/**
 * The JSDoc parser
 */
contract JsDocParser is IJsDocParser {

  // states of the parsing state machine
  enum ParseState {
    // initial state
    commentStart,
    // in serching for a new or continued description
    descriptionSearch,
    // in processing description
    inDescription,
    // in serching for a new block tag
    tagNameSearch,
    // in processing tag name
    inTagName,
    // in serching for param type or name
    paramAttrSearch,
    // in processing param type
    inParamType,
    // in serching for a new param name
    paramNameSearch,
    // in processing param name
    inParamName,
    // in serching for a new or continued param description
    paramDescSearch,
    // in processing param description
    inParamDesc
  }

  /**
   * Parse source code and extract JSDoc comments.
   * @param code source code
   * @return JSDoc comments
   */
  function parse(string calldata code) external pure override returns (IJsDocParser.JsDocComment[] memory) {
    bytes calldata sourceBytes = bytes(code);
    uint commentCount = 0;
    uint commentArrayPageSize = 10;
    IJsDocParser.Context memory context;
    context.eofPos = uint(sourceBytes.length);
    IJsDocParser.JsDocComment[] memory comments = new IJsDocParser.JsDocComment[](commentArrayPageSize);

    while (context.currentPos < context.eofPos) {
      IJsDocParser.JsDocComment memory comment = _nextComment(sourceBytes, context);
      if (comment.lines.length == 0) {
        continue;
      }
      comments[commentCount++] = comment;

      if (commentCount % commentArrayPageSize == 0) {
        comments = _resize(comments, comments.length + commentArrayPageSize);
      }
    }

    // cut of redundant elements
    comments = _resize(comments, commentCount);
    return comments;
  }

  /**
   * Extract a jsdoc comment 
   * @param source bytes sequence of source code.
   * @param context parsing context.
   * @return jsdoc comment.
   */
  function _nextComment(
    bytes calldata source,
    IJsDocParser.Context memory context
  ) private pure returns (IJsDocParser.JsDocComment memory) {
    IJsDocParser.JsDocComment memory comment;
    context.currentPos = _skipSpaces(source, context.currentPos, context.eofPos);
    if (context.eofPos <= context.currentPos) { // ends with space
      return comment;
    }

    IUtf8Char.Utf8Char memory char = Utf8.getNextCharacter(source, context.currentPos);
    if (char.code == 0x2F) { // slash
      IUtf8Char.Utf8Char memory nextChar = Utf8.getNextCharacter(source, context.currentPos + 1);
      if (nextChar.code == 0x2A) { // block comment
        nextChar = Utf8.getNextCharacter(source, context.currentPos + 2);
        if (nextChar.code == 0x2A) { // possible jsdoc comment
          nextChar = Utf8.getNextCharacter(source, context.currentPos + 3);
          if (nextChar.code != 0x2A) { // jsdoc comment
            comment = _readJsDocComment(source, context);
            context.currentPos += comment.sizeInBytes;
          } else { // starts with /***. normal comment
            context.currentPos += 4;
          }
        } else {
          context.currentPos += 3;
        }
      } else {
        context.currentPos += 2;
      }
    } else {
      context.currentPos += 1;
    }
    
    return comment;
  }

  /**
   * Extract a jsdoc comment
   * @param source bytes sequence of source code.
   * @param context parsing context.
   * @return comment jsdoc comment.
   */
  function _readJsDocComment(
    bytes calldata source,
    IJsDocParser.Context memory context
  ) private pure returns (IJsDocParser.JsDocComment memory comment) {
    IJsDocParser.Context memory localContext;
    localContext.lineStartPos = context.currentPos;
    localContext.currentPos = context.currentPos + 3; // skip /**
    localContext.currentLine = context.currentLine;
    localContext.eofPos = context.eofPos;
    localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
    
    ParseState curState = ParseState.commentStart;
    IJsDocParser.JsDocTag memory curTag;
    while (localContext.currentPos < localContext.eofPos) {
      if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
        localContext.currentPos += 2;
        _fixComment(comment, localContext, curState, curTag, source);
        return comment;
      }
      IUtf8Char.Utf8Char memory char = Utf8.getNextCharacter(source, localContext.currentPos);

      if (curState == ParseState.commentStart) {
        if (char.code == 0x2A) { // *
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = localContext.currentPos;
          ++localContext.currentPos;
          curState = ParseState.inDescription;
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.descriptionSearch;
        } else if (char.code == 0x40) { // @
          // non-space char follows @ ? 
          if (
            Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x20 ||
            _isEndMarker(localContext.currentPos + 1, localContext.currentPos + 2, source)
          ) {
            // it's part of description
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = ++localContext.currentPos;
            curState = ParseState.inDescription;
          } else {
            // found block tag
            localContext.tokenStartPos = ++localContext.currentPos;
            localContext.tokenEndPos = localContext.tokenStartPos + 1;
            curState = ParseState.inTagName;
          }
        } else {
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inDescription;
        }
      } else if (curState == ParseState.descriptionSearch) {
        if (char.code == 0x2A) { // *
          ++localContext.currentPos;
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          bool isBlockTagFollowing = _isStartedWithBlockTagMarker(localContext.currentPos, localContext.eofPos, source);
          if (isBlockTagFollowing) {
            // current tag ended. so flush and search next one
            _addAndFlushTag(comment, curTag);
            curState = ParseState.tagNameSearch;
          } else {
            // description body found
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = localContext.tokenStartPos;
            curState = ParseState.inDescription;
          }
        } else if (Utf8.isNewLine(char.code)) {
          if (_isDescriptionContinued(localContext.currentPos + char.size, localContext.eofPos, source)) {
            localContext.tokenEndPos += char.size; // add CR
          }
          _updateDescription(comment, localContext, source);
          _fixLine(comment, localContext, source, char.size);
        } else if (char.code == 0x40) { // @
          ++localContext.currentPos;
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x20) {
            // it's part of description
            curState = ParseState.inDescription;
          } else {
            // found block tag
            curState = ParseState.inDescription;
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = localContext.tokenStartPos + 1;
            curState = ParseState.inTagName;
          }
        } else {
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inDescription;
        }
      } else if (curState == ParseState.inDescription) {
        if (char.code == 0x2A) { // *
          localContext.tokenEndPos = ++localContext.currentPos;
        } else if (Utf8.isNewLine(char.code)) {
          if (_isDescriptionContinued(localContext.currentPos + char.size, localContext.eofPos, source)) {
            localContext.tokenEndPos += char.size; // add CR
          }
          _updateDescription(comment, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.descriptionSearch;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.tagNameSearch) {
        if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, source, char.size);
        } else if (char.code == 0x40) { // @
          // found tag name
          ++localContext.currentPos;
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = localContext.tokenStartPos + 1;
          curState = ParseState.inTagName;
        } else {
          // possible description
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.descriptionSearch;
        }
      } else if (curState == ParseState.inTagName) {
        if (Utf8.isNewLine(char.code)) {
          // tag name fixed, start searching param description
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else if (char.code == 0x20) { // space
          // tag name fixed, start searching param type/name
          _updateTagAttr(curTag, curState, localContext, source);
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          curState = ParseState.paramAttrSearch;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.paramAttrSearch) {
        if (Utf8.isNewLine(char.code)) {
          // no param type or name, start searching param description
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else if (char.code == 0x7B) { // {
          // found param type
          ++localContext.currentPos;
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = localContext.tokenStartPos;
          curState = ParseState.inParamType;
        } else {
          // found param name
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamName;
        }
      } else if (curState == ParseState.inParamType) {
        if (Utf8.isNewLine(char.code)) {
          // param type continues on next line
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          localContext.tokenStartPos = localContext.currentPos; 
          localContext.tokenEndPos = localContext.currentPos;
        } else if (char.code == 0x7D) { // }
          // param type fixed. start searching param name
          _updateTagAttr(curTag, curState, localContext, source);
          ++localContext.currentPos;
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          curState = ParseState.paramNameSearch;
        } else if (char.code == 0x20) { // space
          // intermediate spaces are part of the type name, trailing spaces are excluded
          uint skippedPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          if (Utf8.getNextCharacter(source, skippedPos).code == 0x7D) {
            // skip spaces up to }
            localContext.tokenEndPos = localContext.currentPos; // before the spaces
            localContext.currentPos = skippedPos;
          } else {
            ++localContext.currentPos;
            localContext.tokenEndPos = localContext.currentPos;
          }
        } else {
          ++localContext.currentPos;
          localContext.tokenEndPos = localContext.currentPos;
        }
      } else if (curState == ParseState.paramNameSearch) {
        if (Utf8.isNewLine(char.code)) {
          // no param name found. start searching param description
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else {
          // found param name
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamName;
        }
      } else if (curState == ParseState.inParamName) {
        if (Utf8.isNewLine(char.code)) {
          // param name fixed. start searching param description
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else if (char.code == 0x20) { // space
          // param name fixed. start searching param description
          localContext.tokenEndPos = localContext.currentPos;
          _updateTagAttr(curTag, curState, localContext, source);
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          curState = ParseState.paramDescSearch;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.paramDescSearch) {
        if (char.code == 0x2A || char.code == 0x40) { // *
          if (char.code == 0x2A) {
            ++localContext.currentPos; // '*' not to be included tag or desc
          }
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          bool isBlockTagFollowing = _isStartedWithBlockTagMarker(localContext.currentPos, localContext.eofPos, source);
          if (isBlockTagFollowing) {
            // current tag ended. so flush and search next one
            _addAndFlushTag(comment, curTag);
            curState = ParseState.tagNameSearch;
          } else {
            // description body found
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = localContext.tokenStartPos;
            curState = ParseState.inParamDesc;
          }
        } else if (Utf8.isNewLine(char.code)) {
          if (_isDescriptionContinued(localContext.currentPos + char.size, localContext.eofPos, source)) {
            localContext.tokenEndPos += char.size; // add CR
          }
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
        } else {
          // found param description
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamDesc;
        }
      } else if (curState == ParseState.inParamDesc) {
        if (Utf8.isNewLine(char.code)) {
          if (_isDescriptionContinued(localContext.currentPos + char.size, localContext.eofPos, source)) {
            localContext.tokenEndPos += char.size; // add CR
          }
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else if (char.code == 0x20) { // space
          // intermediate spaces are part of the param description, trailing spaces are excluded
          uint skippedPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          if (_isEndMarker(skippedPos, skippedPos + 1, source)) {
            // skip spaces up to end marker
            localContext.tokenEndPos = localContext.currentPos; // before the space
            localContext.currentPos = skippedPos;
          } else {
            ++localContext.currentPos;
            localContext.tokenEndPos = localContext.currentPos;
          }
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      }
    }

    revert('comment not closed');
  }

  /**
   * Add raw string for one line of comment
   * @param comment JSDoc comment
   * @param source source code
   * @param start start point of the line
   * @param end end point of the line
   * @param lineNum line number
   */
  function _addCommentLine(IJsDocParser.JsDocComment memory comment, bytes calldata source, uint start, uint end, uint lineNum) private pure returns (IJsDocParser.JsDocComment memory) {
    IJsDocParser.CommentLine[] memory newLines = new IJsDocParser.CommentLine[](comment.lines.length + 1);
    for (uint i = 0; i < comment.lines.length; ++i) {
      newLines[i] = comment.lines[i];
    }
    bytes memory rawExpression = source[start:end];
    newLines[newLines.length - 1] = IJsDocParser.CommentLine({
      rawExpression: string(rawExpression),
      lineNum: lineNum
    });
    comment.lines = newLines;
    comment.sizeInBytes += rawExpression.length;
  }
  
  /**
   * Add block tag to commen and clear current tag.
   * @param comment JSDoc comment
   * @param tag block tag
   */
  function _addAndFlushTag(IJsDocParser.JsDocComment memory comment, IJsDocParser.JsDocTag memory tag) private pure {
    if (bytes(tag.tagName).length > 0) {
      IJsDocParser.JsDocTag[] memory newTags = new IJsDocParser.JsDocTag[](comment.tags.length + 1);
      for (uint i = 0; i < comment.tags.length; ++i) {
        newTags[i] = comment.tags[i];
      }
      newTags[newTags.length - 1] = IJsDocParser.JsDocTag({
        tagName: tag.tagName,
        paramName: tag.paramName,
        paramDesc: tag.paramDesc,
        paramType: tag.paramType,
        lineIndex: tag.lineIndex
      });
      comment.tags = newTags;
    }
    tag.tagName = '';
    tag.paramName = '';
    tag.paramDesc = '';
    tag.paramType = '';
  }

  /**
   * Update tag attribute with current parsed value
   * @param tag block tag
   * @param state current state
   * @param context parsing context
   * @param source source code
   */
  function _updateTagAttr(
    IJsDocParser.JsDocTag memory tag,
    ParseState state,
    IJsDocParser.Context memory context,
    bytes calldata source
  ) private pure {
    if (context.tokenEndPos <= context.tokenStartPos) {
      return;
    }
    string memory value = string(source[context.tokenStartPos:context.tokenEndPos]);
    context.tokenStartPos = context.tokenEndPos;
    if (state == ParseState.inTagName) {
      tag.tagName = string.concat(tag.tagName, value);
    } else if (state == ParseState.inParamType) {
      tag.paramType = string.concat(tag.paramType, value);
    } else if (state == ParseState.inParamName) {
      tag.paramName = string.concat(tag.paramName, value);
    } else if (state == ParseState.inParamDesc || state == ParseState.paramDescSearch) {
      tag.paramDesc = string.concat(tag.paramDesc, value);
    }
  }

  /**
   * Set new line context
   * @param context parsing context
   * @param source source code
   * @param nwSize size in bytes of new line delimiter
   */
  function _setNewLineContext(JsDocParser.Context memory context, bytes calldata source, uint nwSize) private pure {
    ++context.currentLine;
    context.currentPos += nwSize;
    context.lineStartPos = context.currentPos;
    context.currentPos = _skipSpaces(source, context.currentPos, context.eofPos);
  }

  /**
   * Update comment description
   * @param comment JSDoc comment
   * @param context parsing context
   * @param source source code
   */
  function _updateDescription(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    bytes calldata source
  ) private pure {
    string memory lineDesc = string(source[context.tokenStartPos:context.tokenEndPos]);
    comment.description = string.concat(comment.description, lineDesc);
    context.tokenStartPos = context.tokenEndPos;
  }
  
  /**
   * Set current parsed value and fix comment.
   * @param comment JSDoc comment
   * @param context parsing context
   * @param state current state
   * @param tag block tag
   * @param source source code
   */
  function _fixComment(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    ParseState state,
    IJsDocParser.JsDocTag memory tag,
    bytes calldata source
  ) private pure {
    _addCommentLine(comment, source, context.lineStartPos, context.currentPos, context.currentLine);
    if (
      state == ParseState.commentStart ||
      state == ParseState.descriptionSearch ||
      state == ParseState.inDescription
    ) {
      _updateDescription(comment, context, source);
    } else {
      _updateTagAttr(tag, state, context, source);
      _addAndFlushTag(comment, tag);
    }
  }
  
  /**
   * Set current parsed value and fix line.
   * @param comment JSDoc comment
   * @param context parsing context
   * @param source source code
   * @param nwSize size in bytes of new line delimiter
   */
  function _fixLine(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    bytes calldata source,
    uint nwSize
  ) private pure {
    _addCommentLine(comment, source, context.lineStartPos, context.currentPos, context.currentLine);
    _setNewLineContext(context, source, nwSize);
  }
  
  /**
   * skip spaces
   * @param source bytes sequence of source code.
   * @param startPos start position.
   * @param eofPos end of file position.
   */
  function _skipSpaces(
    bytes calldata source,
    uint startPos,
    uint eofPos
  ) private pure returns (uint){
    uint curPos = startPos;
    while (curPos < eofPos) {
      IUtf8Char.Utf8Char memory currentChar = Utf8.getNextCharacter(source, curPos);
      if (
        currentChar.code == 0x20 || // space
        currentChar.code == 0xC2A0 || // nonBreakingSpace
        currentChar.code == 0x09 // tab
      ) {
        curPos += currentChar.size;
      } else {
        break;
      }
    }
    return curPos;
  }

  /**
   * Check if the specified string is end marker
   * @param startPos start position of the string
   * @param endPos end position of the string
   * @param source source code
   * @return true if the string is end marker
   */
  function _isEndMarker(uint startPos, uint endPos, bytes calldata source) private pure returns (bool) {
    return Utf8.getNextCharacter(source, startPos).code == 0x2A &&
        Utf8.getNextCharacter(source, endPos).code == 0x2F;
  }
  
  /**
   * Check if the string starts with block tag marker
   * @param startPos start position of the string
   * @param eofPos end position of the source code
   * @param source source code
   * @return true if the string starts with block tag marker
   */
  function _isStartedWithBlockTagMarker(uint startPos, uint eofPos, bytes calldata source) private pure returns (bool) {
    uint skippedPos = _skipSpaces(source, startPos, eofPos);
    uint charCode = Utf8.getNextCharacter(source, skippedPos).code;
    if (charCode == 0x40) { // @
      charCode = Utf8.getNextCharacter(source, skippedPos + 1).code;
      return charCode != 0x20; // valid tag
    }
    if (charCode == 0x2A) { // *
      skippedPos = _skipSpaces(source, skippedPos + 1, eofPos);
      charCode = Utf8.getNextCharacter(source, skippedPos).code;
      if (charCode == 0x40) { // @
        charCode = Utf8.getNextCharacter(source, skippedPos + 1).code;
        return charCode != 0x20; // valid tag
      }
    }
    return false;
  }
  
  /**
   * Check if the description continues
   * @param startPos start position of the string
   * @param eofPos end position of the source code
   * @param source source code
   * @return true if the description continues
   */
  function _isDescriptionContinued(uint startPos, uint eofPos, bytes calldata source) private pure returns (bool) {
    uint skippedPos = _skipSpaces(source, startPos, eofPos);
    return !_isEndMarker(skippedPos, skippedPos + 1, source) && !_isStartedWithBlockTagMarker(skippedPos, eofPos, source);
  }

  /**
   * Resize the token array
   * @param comments token array.
   * @param size target size.
   * @return new token array.
   */
  function _resize(IJsDocParser.JsDocComment[] memory comments, uint size) private pure returns (IJsDocParser.JsDocComment[] memory) {
    IJsDocParser.JsDocComment[] memory newArray = new IJsDocParser.JsDocComment[](size);
    for (uint i = 0; i < comments.length && i < size; i++) {
      newArray[i] = comments[i];
    }
    return newArray;
  }
}