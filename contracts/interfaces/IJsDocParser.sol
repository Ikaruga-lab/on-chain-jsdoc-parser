// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IJsDocParser {
  struct JsDocTag {
    string tagName;
    string paramName;
    string paramDesc;
    string paramType;
    uint lineIndex;
  }

  struct CommentLine {
    string rawExpression;
    uint lineNum;
  }

  struct JsDocComment {
    string description;
    CommentLine[] lines;
    JsDocTag[] tags;
    uint sizeInBytes;
  }
  
  // parsing context 
  struct Context {
    // current position in source code byte array
    uint currentPos;
    // current line number
    uint currentLine;
    // end position of source code byte array
    uint eofPos;
    uint lineStartPos;
    uint tokenStartPos;
    uint tokenEndPos;
  }


  function parse(string calldata code) external view returns (JsDocComment[] memory);
}