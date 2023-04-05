// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

/**
 * The proxy for SnippetJS
 */
contract JsDocParserProxy is TransparentUpgradeableProxy {
  constructor(
    address logic,
    address admin,
    bytes memory data
  ) TransparentUpgradeableProxy(logic, admin, data) {}
}