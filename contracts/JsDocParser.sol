// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "hardhat/console.sol";
import './Log.sol';
import './interfaces/IJsDocParser.sol';
import './Utf8.sol';

/**
 * The entry point lexer for tokenizing.
 */
contract JsDocParser is IJsDocParser {

  enum ParseState {
    commentStart,
    inDescription,
    newLine,
    inLineText,
    blockTagStart,
    inTagName,
    tagAttrStart,
    inParamType,
    tagNameStart,
    inParamName,
    tagDescStart,
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
    _skipSpaces(source, context);
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

    _skipSpaces(source, localContext);
    
    ParseState curState = ParseState.commentStart;
    IJsDocParser.JsDocTag memory curTag;
    while (localContext.currentPos < localContext.eofPos) {
      IUtf8Char.Utf8Char memory char = Utf8.getNextCharacter(source, localContext.currentPos);
      console.log('CHAR %d', char.code);

      if (curState == ParseState.commentStart) {
        console.log('IN commentStart');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            console.log('fix comment_commentStart');
            _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
            comment.description = string(source[localContext.tokenStartPos:localContext.tokenEndPos]);
            return comment;
          } else {
            console.log('TO inDescription_commentStart');
            console.log('start %d', localContext.currentPos);
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = ++localContext.currentPos;
            curState = ParseState.inDescription;
          }
        } else if (Utf8.isNewLine(char.code)) {
          console.log('TO newLine_commentStart');
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.newLine;
        } else if (char.code == 0x40) { // @
          console.log('TO inTagName_commentStart');
          ++localContext.currentPos;
          curState = ParseState.inTagName;
        } else {
          console.log('TO inDescription_commentStart');
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inDescription;
        }
      } else if (curState == ParseState.inDescription) {
        console.log('IN inDescription');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            console.log('fix comment2');
            console.log('start pos %d', localContext.tokenStartPos);
            _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
            comment.description = string(source[localContext.tokenStartPos:localContext.tokenEndPos]);
            return comment;
          } else {
            localContext.tokenEndPos = ++localContext.currentPos;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.newLine;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.newLine) {
        console.log('IN newLine');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
            return comment;
          } else {
            ++localContext.currentPos;
            curState = ParseState.blockTagStart;
            _skipSpaces(source, context);
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.newLine;
        // } else if (char.code == 0x20) { // space
        } else if (char.code == 0x7B || char.code == 0x7D) {
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inLineText;
        } else if (char.code == 0x40) { // @
          ++localContext.currentPos;
          curState = ParseState.inTagName;
        }
      } else if (curState == ParseState.inLineText) {
        console.log('IN inLineText');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
            return comment;
          } else {
            localContext.tokenEndPos = ++localContext.currentPos;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.newLine;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.blockTagStart) {
        console.log('IN blockTagStart');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            _addCommentLine(comment, source, localContext.lineStartPos, localContext.currentPos + 2, localContext.currentLine);
            return comment;
          } else {
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = ++localContext.currentPos;
            curState = ParseState.inLineText;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, source, char.size);
          curState = ParseState.newLine;
        // } else if (char.code == 0x20) { // space
        } else if (char.code == 0x7B || char.code == 0x7D) { // {}
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inLineText;
        } else if (char.code == 0x40) { // @
          ++localContext.currentPos;
          curState = ParseState.inTagName;
        }
      } else if (curState == ParseState.inTagName) {
        console.log('IN inTagName');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            localContext.currentPos += 2;
            _fixComment(comment, localContext, curState, curTag, source);
            return comment;
          } else {
            localContext.tokenEndPos = ++localContext.currentPos;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, curState, curTag, source, char.size);
          curState = ParseState.newLine;
        } else if (char.code == 0x20) { // space
          _fixTagAttr(curTag, curState, localContext.tokenStartPos, localContext.tokenEndPos, source);
          _skipSpaces(source, localContext);
          curState = ParseState.tagAttrStart;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.tagAttrStart) {
        console.log('IN tagAttrStart');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            localContext.currentPos += 2;
            _fixComment(comment, localContext, curState, curTag, source);
            return comment;
          } else {
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = ++localContext.currentPos;
            curState = ParseState.inParamName;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, curState, curTag, source, char.size);
          curState = ParseState.newLine;
        // } else if (char.code == 0x20) { // space
        } else if (char.code == 0x7B) { // {
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamType;
        } else {
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamName;
        }
      } else if (curState == ParseState.inParamType) {
        console.log('IN inParamType');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            localContext.currentPos += 2;
            _fixComment(comment, localContext, curState, curTag, source);
            return comment;
          } else {
            localContext.tokenEndPos = ++localContext.currentPos;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, curState, curTag, source, char.size);
          curState = ParseState.newLine;
        } else if (char.code == 0x7D) { // }
          localContext.tokenEndPos = ++localContext.currentPos;
          _fixTagAttr(curTag, curState, localContext.tokenStartPos, localContext.tokenEndPos, source);
          _skipSpaces(source, localContext);
          curState = ParseState.tagNameStart;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.tagNameStart) {
        console.log('IN tagNameStart');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            localContext.currentPos += 2;
            _fixComment(comment, localContext, curState, curTag, source);
            return comment;
          } else {
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = ++localContext.currentPos;
            curState = ParseState.inParamName;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, curState, curTag, source, char.size);
          curState = ParseState.newLine;
        } else {
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamName;
        }
      } else if (curState == ParseState.inParamName) {
        console.log('IN inParamName');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            localContext.currentPos += 2;
            _fixComment(comment, localContext, curState, curTag, source);
            return comment;
          } else {
            localContext.tokenEndPos = ++localContext.currentPos;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, curState, curTag, source, char.size);
          curState = ParseState.newLine;
        } else if (char.code == 0x20) { // space
          localContext.tokenEndPos = localContext.currentPos;
          _fixTagAttr(curTag, curState, localContext.tokenStartPos, localContext.tokenEndPos, source);
          _skipSpaces(source, localContext);
          curState = ParseState.tagDescStart;
        } else {
          localContext.tokenEndPos = ++localContext.currentPos;
        }
      } else if (curState == ParseState.tagDescStart) {
        console.log('IN tagDescStart');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            localContext.currentPos += 2;
            _fixComment(comment, localContext, curState, curTag, source);
            return comment;
          } else {
            localContext.tokenStartPos = localContext.currentPos;
            localContext.tokenEndPos = ++localContext.currentPos;
            curState = ParseState.inParamDesc;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, curState, curTag, source, char.size);
          curState = ParseState.newLine;
        } else {
          localContext.tokenStartPos = localContext.currentPos;
          localContext.tokenEndPos = ++localContext.currentPos;
          curState = ParseState.inParamDesc;
        }
      } else if (curState == ParseState.inParamDesc) {
        console.log('IN inParamDesc');
        if (char.code == 0x2A) { // *
          if (Utf8.getNextCharacter(source, localContext.currentPos + 1).code == 0x2F) { // '/'
            localContext.currentPos += 2;
            _fixComment(comment, localContext, curState, curTag, source);
            return comment;
          } else {
            localContext.tokenEndPos = ++localContext.currentPos;
          }
        } else if (Utf8.isNewLine(char.code)) {
          _fixLine(comment, localContext, curState, curTag, source, char.size);
          curState = ParseState.newLine;
        } else if (char.code == 0x40) { // @
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
  
  function _addTag(IJsDocParser.JsDocComment memory comment, IJsDocParser.JsDocTag memory tag) private pure returns (IJsDocParser.JsDocComment memory) {
    IJsDocParser.JsDocTag[] memory newTags = new IJsDocParser.JsDocTag[](comment.tags.length + 1);
    for (uint i = 0; i < comment.tags.length; ++i) {
      newTags[i] = comment.tags[i];
    }
    newTags[newTags.length - 1] = tag;
    comment.tags = newTags;
  }

  function _fixTagAttr(
    IJsDocParser.JsDocTag memory tag,
    ParseState state,
    uint tokenStartPos,
    uint tokenEndPos,
    bytes calldata source
  ) private pure {
    if (tokenEndPos < tokenStartPos) {
      return;
    }
    string memory value = string(source[tokenStartPos:tokenEndPos]);
    if (state == ParseState.inTagName) {
      tag.tagName = value;
    } else if (state == ParseState.inParamType) {
      tag.paramType = value;
    } else if (state == ParseState.inParamName) {
      tag.paramName = value;
    } else if (state == ParseState.inParamDesc) {
      tag.paramDesc = value;
    }
  }

  function _setNewLineContext(JsDocParser.Context memory context, bytes calldata source, uint nwSize) private view {
    ++context.currentLine;
    context.currentPos += nwSize;
    context.lineStartPos = context.currentPos;
    _skipSpaces(source, context);
    context.tokenStartPos = context.currentPos;
    context.tokenEndPos = context.currentPos;
  }

  function _fixComment(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    ParseState state,
    IJsDocParser.JsDocTag memory tag,
    bytes calldata source
  ) private pure {
    _addCommentLine(comment, source, context.lineStartPos, context.currentPos, context.currentLine);
    _fixTagAttr(tag, state, context.tokenStartPos, context.tokenEndPos, source);
    if (bytes(tag.tagName).length > 0) {
      _addTag(comment, tag);
    }
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
  
  function _fixLine(
    IJsDocParser.JsDocComment memory comment,
    IJsDocParser.Context memory context,
    ParseState state,
    IJsDocParser.JsDocTag memory tag,
    bytes calldata source,
    uint nwSize
  ) private view {
    _addCommentLine(comment, source, context.lineStartPos, context.currentPos, context.currentLine);
    _fixTagAttr(tag, state, context.tokenStartPos, context.tokenEndPos, source);
    if (bytes(tag.tagName).length > 0) {
      _addTag(comment, tag);
    }
    _setNewLineContext(context, source, nwSize);
    tag.tagName = '';
    tag.paramName = '';
    tag.paramDesc = '';
    tag.paramType = '';
  }
  
  /**
   * skip spaces
   * @param source bytes sequence of source code.
   * @param context Tokenization context.
   */
  function _skipSpaces(
    bytes calldata source,
    IJsDocParser.Context memory context 
  ) private view {
    while (context.currentPos < context.eofPos) {
      IUtf8Char.Utf8Char memory currentChar = Utf8.getNextCharacter(source, context.currentPos);
      console.log('S CHAR %d', currentChar.code);
      if (
        currentChar.code == 0x20 || // space
        currentChar.code == 0xC2A0 || // nonBreakingSpace
        currentChar.code == 0x09 // tab
      ) {
        context.currentPos += currentChar.size;
      } else {
        break;
      }
    }
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