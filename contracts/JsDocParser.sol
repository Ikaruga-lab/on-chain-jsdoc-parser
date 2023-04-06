// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "hardhat/console.sol";
import './Log.sol';
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

  function parse(string calldata code) external view override returns (IJsDocParser.JsDocComment[] memory) {
    bytes calldata sourceBytes = bytes(code);
    uint commentCount = 0;
    uint commentArrayPageSize = 10;
    IJsDocParser.Context memory context;
    context.eofPos = uint(sourceBytes.length);
    IJsDocParser.JsDocComment[] memory comments = new IJsDocParser.JsDocComment[](commentArrayPageSize);

    while (context.currentPos < context.eofPos) {
      IJsDocParser.JsDocComment memory comment = _nextComment(sourceBytes, context);
      Log.log(comment);
      if (comment.lines.length == 0) {
        continue;
      }
      comments[commentCount++] = comment;

      if (commentCount % commentArrayPageSize == 0) {
        comments = _resize(comments, comments.length + commentArrayPageSize);
      }
    }

    // cut of redundant elements
    console.log('COUNT %d', commentCount);
    comments = _resize(comments, commentCount);
    return comments;
  }

  /**
   * Extract a token. Read next character and dispach a tokenizing task to the appropriate lexer.
   * @param source bytes sequence of source code.
   * @param context Tokenization context.
   * @return The token.
   */
  function _nextComment(
    bytes calldata source,
    IJsDocParser.Context memory context
  ) private view returns (IJsDocParser.JsDocComment memory) {
    console.log('_nextComment');
    IJsDocParser.JsDocComment memory comment;
    context.currentPos = _skipSpaces(source, context.currentPos, context.eofPos);
    if (context.eofPos <= context.currentPos) { // ends with space
      console.log('END comment');
      return comment;
    }

    IUtf8Char.Utf8Char memory char = Utf8.getNextCharacter(source, context.currentPos);
    if (char.code == 0x2F) { // slash
      console.log('slash');
      IUtf8Char.Utf8Char memory nextChar = Utf8.getNextCharacter(source, context.currentPos + 1);
      if (nextChar.code == 0x2A) { // block comment
        console.log('block comment');
        nextChar = Utf8.getNextCharacter(source, context.currentPos + 2);
        if (nextChar.code == 0x2A) { // possible jsdoc comment
          console.log('possible jsdoc comment');
          nextChar = Utf8.getNextCharacter(source, context.currentPos + 3);
          if (nextChar.code != 0x2A) { // jsdoc comment
            console.log('jsdoc comment');
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
  ) private view returns (IJsDocParser.JsDocComment memory comment) {
    console.log('IN _readJsDocComment');
    IJsDocParser.Context memory localContext;
    localContext.lineStartPos = context.currentPos;
    localContext.currentPos = context.currentPos + 3; // skip /**
    localContext.currentLine = context.currentLine;
    localContext.eofPos = context.eofPos;
    localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
    
    ParseState curState = ParseState.commentStart;
    IJsDocParser.JsDocTag memory curTag;
    while (localContext.currentPos < localContext.eofPos) {
      IUtf8Char.Utf8Char memory char = Utf8.getNextCharacter(source, localContext.currentPos);
      console.log('CHAR %d', char.code);

      if (curState == ParseState.commentStart) {
        console.log('IN commentStart');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix comment_commentStart');
          _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
          _updateDescription(comment, localContext, source);
          return comment;
        }
        if (char.code == 0x2A) { // *
          console.log('TO inDescription_commentStart');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = localContext.currentPos;
          ++localContext.currentPos;
          curState = ParseState.inDescription;
        } else if (Utf8.isNewLine(char.code)) {
          console.log('TO descriptionSearch commentStart');
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.descriptionSearch;
        } else if (char.code == 0x40) { // @
          if (
            Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x20 ||
            _isEndMarker(localContext.currentPos + 1, localContext.currentPos + 2, source)
          ) {
            console.log('TO inDescription_commentStart2');
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = ++localContext.currentPos;
            curState = ParseState.inDescription;
          } else {
            console.log('TO inTagName_commentStart');
            localContext.tokenStartPos = ++localContext.currentPos;
            localContext.tokenEndPos = localContext.tokenStartPos + 1;
            curState = ParseState.inTagName;
          }
        } else {
          console.log('TO inDescription_commentStart3');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inDescription;
        }
      } else if (curState == ParseState.descriptionSearch) {
        console.log('IN descriptionSearch');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix comment_descriptionSearch');
          _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
          _updateDescription(comment, localContext, source);
          return comment;
        }
        if (char.code == 0x2A) { // *
          console.log('TO inDescription_descriptionSearch');
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
          console.log('TO descriptionSearch descriptionSearch');
          // is description continued?
          uint skippedPos = _skipSpaces(source, localContext.currentPos + char.size, localContext.eofPos);
          bool descEnded = _isEndMarker(skippedPos, skippedPos + 1, source) || _isStartedWithBlockTagMarker(skippedPos, localContext.eofPos, source);
          if (!descEnded) {
            localContext.tokenEndPos += char.size; // add CR
          }
          _updateDescription(comment, localContext, source);
          _fixLine(comment, localContext, source, char.size);
        } else if (char.code == 0x40) { // @
          ++localContext.currentPos;
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x20) { // invalid tag
            console.log('TO inDescription_descriptionSearch2');
            curState = ParseState.inDescription;
          } else {
            console.log('TO inTagName_descriptionSearch');
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = localContext.tokenStartPos + 1;
            curState = ParseState.inTagName;
          }
        } else {
          console.log('TO inDescription_descriptionSearch3');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inDescription;
        }
      } else if (curState == ParseState.inDescription) {
        console.log('IN inDescription');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix comment2');
          _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
          _updateDescription(comment, localContext, source);
          console.log('TOKNE STT %d', localContext.tokenStartPos);
          console.log('TOKNE END %d', localContext.tokenEndPos);
          return comment;
        }
        if (char.code == 0x2A) { // *
          localContext.tokenEndPos = ++localContext.currentPos;
        } else if (Utf8.isNewLine(char.code)) {
          console.log('TO descriptionSearch_inDescription');
          // is description continued?
          uint skippedPos = _skipSpaces(source, localContext.currentPos + char.size, localContext.eofPos);
          bool descEnded = _isEndMarker(skippedPos, skippedPos + 1, source) || _isStartedWithBlockTagMarker(skippedPos, localContext.eofPos, source);
          if (!descEnded) {
            localContext.tokenEndPos += char.size; // add CR
          }
          
          _updateDescription(comment, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.descriptionSearch;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.tagNameSearch) {
        console.log('IN tagNameSearch');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix commment tagNameSearch');
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (Utf8.isNewLine(char.code)) {
          console.log('TO tagNameSearch FROM tagNameSearch');
          _fixLine(comment, localContext, source, char.size);
        } else if (char.code == 0x40) { // @
          console.log('TO inTagName FROM tagNameSearch');
          ++localContext.currentPos;
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = localContext.tokenStartPos + 1;
          curState = ParseState.inTagName;
        } else {
          console.log('TO inLineText FROM tagNameSearch');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.descriptionSearch;
        }
      } else if (curState == ParseState.inTagName) {
        console.log('IN inTagName');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix commment inTagName');
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (Utf8.isNewLine(char.code)) {
          console.log('TO paramDescSearch FROM inTagName');
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else if (char.code == 0x20) { // space
          console.log('TO paramAttrSearch FROM inTagName');
          _updateTagAttr(curTag, curState, localContext, source);
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          curState = ParseState.paramAttrSearch;
        } else {
          console.log('extend TAG NAME');
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.paramAttrSearch) {
        console.log('IN paramAttrSearch');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix commment paramAttrSearch');
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (char.code == 0x2A) { // *
          console.log('TO inParamName FROM paramAttrSearch');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamName;
        } else if (Utf8.isNewLine(char.code)) {
          console.log('TO paramDescSearch FROM paramAttrSearch');
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        // } else if (char.code == 0x20) { // space
        } else if (char.code == 0x7B) { // {
          ++localContext.currentPos;
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          console.log('TO inParamType FROM paramAttrSearch');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = localContext.tokenStartPos;
          curState = ParseState.inParamType;
        } else {
          console.log('TO inParamName FROM paramAttrSearch');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamName;
        }
      } else if (curState == ParseState.inParamType) {
        console.log('IN inParamType');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix commment inParamType');
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (Utf8.isNewLine(char.code)) {
          console.log('newline ParamType');
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          localContext.tokenStartPos = localContext.currentPos; 
          localContext.tokenEndPos = localContext.currentPos;
        } else if (char.code == 0x7D) { // }
          console.log('TO paramNameSearch FROM inParamType');
          _updateTagAttr(curTag, curState, localContext, source);
          ++localContext.currentPos;
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          curState = ParseState.paramNameSearch;
        } else if (char.code == 0x20) { // space
          console.log('expand ParamType with space');
          uint skippedPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          if (Utf8.getNextCharacter(source, skippedPos).code == 0x7D) {
            // skip spaces up to }
            console.log('skip spaces up to }');
            localContext.tokenEndPos = localContext.currentPos; // before the spaces
            localContext.currentPos = skippedPos;
          } else {
            ++localContext.currentPos;
            localContext.tokenEndPos = localContext.currentPos;
          }
        } else {
          console.log('expand ParamType');
          ++localContext.currentPos;
          localContext.tokenEndPos = localContext.currentPos;
        }
      } else if (curState == ParseState.paramNameSearch) {
        console.log('IN paramNameSearch');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix commment paramNameSearch');
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (Utf8.isNewLine(char.code)) {
          console.log('TO paramDescSearch FROM paramNameSearch');
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else {
          console.log('TO newLine FROM inParamName');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamName;
        }
      } else if (curState == ParseState.inParamName) {
        console.log('IN inParamName');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (char.code == 0x2A) { // *
          localContext.tokenEndPos = ++localContext.currentPos;
        } else if (Utf8.isNewLine(char.code)) {
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else if (char.code == 0x20) { // space
          localContext.tokenEndPos = localContext.currentPos;
          _updateTagAttr(curTag, curState, localContext, source);
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          curState = ParseState.paramDescSearch;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.paramDescSearch) {
        console.log('IN paramDescSearch');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix commment paramDescSearch');
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (char.code == 0x2A || char.code == 0x40) { // *
          if (char.code == 0x2A) {
            ++localContext.currentPos; // '*' not to be included tag or desc
          }
          localContext.currentPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          bool isBlockTagFollowing = _isStartedWithBlockTagMarker(localContext.currentPos, localContext.eofPos, source);
          if (isBlockTagFollowing) {
            // current tag ended. so flush and search next one
            console.log('TO tagNameSearch FROM paramDescSearch');
            _addAndFlushTag(comment, curTag);
            curState = ParseState.tagNameSearch;
          } else {
            // description body found
            console.log('TO inParamDesc FROM paramDescSearch');
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = localContext.tokenStartPos;
            curState = ParseState.inParamDesc;
          }
        } else if (Utf8.isNewLine(char.code)) {
          console.log('TO paramDescSearch FROM paramDescSearch');
          // is description continued?
          uint skippedPos = _skipSpaces(source, localContext.currentPos + char.size, localContext.eofPos);
          bool descEnded = _isEndMarker(skippedPos, skippedPos + 1, source) || _isStartedWithBlockTagMarker(skippedPos, localContext.eofPos, source);
          if (!descEnded) {
            localContext.tokenEndPos += char.size; // add CR
          }
          _updateTagAttr(curTag, ParseState.inParamDesc, localContext, source);
          _fixLine(comment, localContext, source, char.size);
        } else {
          console.log('TO inParamDesc FROM paramDescSearch');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamDesc;
        }
      } else if (curState == ParseState.inParamDesc) {
        console.log('IN inParamDesc');
        if (_isEndMarker(localContext.currentPos, localContext.currentPos + 1, source)) {
          console.log('fix commment inParamDesc');
          localContext.currentPos += 2;
          _fixComment(comment, localContext, curState, curTag, source);
          return comment;
        }
        if (Utf8.isNewLine(char.code)) {
          console.log('TO paramDescSearch FROM inParamDesc');

          // is param description continued?
          uint skippedPos = _skipSpaces(source, localContext.currentPos + char.size, localContext.eofPos);
          bool descEnded = _isEndMarker(skippedPos, skippedPos + 1, source) || _isStartedWithBlockTagMarker(skippedPos, localContext.eofPos, source);
          if (!descEnded) {
            localContext.tokenEndPos += char.size; // add CR
          }
          _updateTagAttr(curTag, curState, localContext, source);
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.paramDescSearch;
        } else if (char.code == 0x20) { // space
          console.log('expand paramDesc with space');
          uint skippedPos = _skipSpaces(source, localContext.currentPos, localContext.eofPos);
          if (_isEndMarker(skippedPos, skippedPos + 1, source)) {
            // skip spaces up to end marker
            console.log('skip spaces up to */');
            localContext.tokenEndPos = localContext.currentPos; // before the space
            localContext.currentPos = skippedPos;
          } else {
            ++localContext.currentPos;
            localContext.tokenEndPos = localContext.currentPos;
          }
        } else {
          console.log('expand paramDesc');
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      }
    }

    revert('comment not closed');
  }

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
  
  function _addAndFlushTag(IJsDocParser.JsDocComment memory comment, IJsDocParser.JsDocTag memory tag) private pure returns (IJsDocParser.JsDocComment memory) {
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

  function _updateTagAttr(
    IJsDocParser.JsDocTag memory tag,
    ParseState state,
    IJsDocParser.Context memory context,
    bytes calldata source
  ) private view {
    if (context.tokenEndPos <= context.tokenStartPos) {
      return;
    }
    string memory value = string(source[context.tokenStartPos:context.tokenEndPos]);
    context.tokenStartPos = context.tokenEndPos;
    if (state == ParseState.inTagName) {
      tag.tagName = string.concat(tag.tagName, value);
    } else if (state == ParseState.inParamType) {
      console.log('ADD TYPE %s', value);
      tag.paramType = string.concat(tag.paramType, value);
      console.log('TOTAL TYPE %s', tag.paramType);
    } else if (state == ParseState.inParamName) {
      tag.paramName = string.concat(tag.paramName, value);
    } else if (state == ParseState.inParamDesc) {
      console.log('ADD DESC %s', value);
      tag.paramDesc = string.concat(tag.paramDesc, value);
      console.log('TOTAL DESC %s', tag.paramDesc);
    }
  }

  function _setNewLineContext(JsDocParser.Context memory context, bytes calldata source, uint nwSize) private view {
    ++context.currentLine;
    context.currentPos += nwSize;
    context.lineStartPos = context.currentPos;
    context.currentPos = _skipSpaces(source, context.currentPos, context.eofPos);
  }

  function _updateDescription(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    bytes calldata source
  ) private view {
    string memory lineDesc = string(source[context.tokenStartPos:context.tokenEndPos]);
    comment.description = string.concat(comment.description, lineDesc);
    context.tokenStartPos = context.tokenEndPos;
    console.log('ADD DESC %s', lineDesc);
    console.log('TOTAL DESC %s', comment.description);
  }
  
  function _fixComment(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    ParseState state,
    IJsDocParser.JsDocTag memory tag,
    bytes calldata source
  ) private view {
    _addCommentLine(comment, source, context.lineStartPos, context.currentPos, context.currentLine);
    _updateTagAttr(tag, state, context, source);
    console.log('param desc %s', tag.paramDesc);
    console.log('add tag %s', tag.paramDesc);
    _addAndFlushTag(comment, tag);
  }
  
  function _fixLine(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    bytes calldata source,
    uint nwSize
  ) private view {
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
  ) private view returns (uint){
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

  function _isEndMarker(uint startPos, uint endPos, bytes calldata source) private pure returns (bool) {
    return Utf8.getNextCharacter(source, startPos).code == 0x2A &&
        Utf8.getNextCharacter(source, endPos).code == 0x2F;
  }
  
  function _isStartedWithBlockTagMarker(uint startPos, uint eofPos, bytes calldata source) private view returns (bool) {
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