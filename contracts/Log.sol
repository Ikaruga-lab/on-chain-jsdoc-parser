// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "hardhat/console.sol";
import './interfaces/IJsDocParser.sol';

library Log {
  function log(IJsDocParser.JsDocComment memory comment) internal view {
    console.log('[JsDocComment]');
    console.log('  description: %s', comment.description);
    console.log('  sizeInBytes: %d', comment.sizeInBytes);
    console.log('  lines: %d', comment.lines.length);
    console.log('  tags: %d', comment.tags.length);
    for (uint j = 0; j < comment.lines.length; ++j) {
      console.log('  [CommentLine]');
      console.log('    rawExpression: %s', comment.lines[j].rawExpression);
      console.log('    lineNum: %d', comment.lines[j].lineNum);
    }
    for (uint j = 0; j < comment.tags.length; ++j) {
      console.log('  [JsDocTag]');
      console.log('    tagName: %s', comment.tags[j].tagName);
      console.log('    paramName: %s', comment.tags[j].paramName);
      console.log('    paramDesc: %s', comment.tags[j].paramDesc);
      console.log('    paramType: %s', comment.tags[j].paramType);
      console.log('    lineIndex: %d', comment.tags[j].lineIndex);
    }
  }
}