// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import './interfaces/IJsDocParser.sol';

contract MeasureGas {
  function measure(
    IJsDocParser parser,
    string calldata code
  ) external view returns (uint, IJsDocParser.JsDocComment[] memory comments) {
    uint gas = gasleft();
    comments = parser.parse(code);
    return (gas - gasleft(), comments);
  }
}