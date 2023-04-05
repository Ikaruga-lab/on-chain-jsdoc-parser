import { utils, constants } from 'ethers' 

export type AddressSrc = 'fixed' | 'dynamic' | 'dummy' | 'external'

export interface LibRule {
  name: string
  addressSrc: AddressSrc
}

export interface ProxyRule {
  contract: ContractRule 
  addressSrc: AddressSrc
  init?: ArgRule[]
}

export interface ArgRule {
  address?: LibRule
  value?: any
}

export interface ContractRule {
  name: string
  libs?: LibRule[]
  args?: ArgRule[]
  proxy?: ProxyRule
  addressSrc: AddressSrc
}

export interface ModuleRule {
  name: string
  contracts: ContractRule[]
}

type DeployRules = {[key:string]: ModuleRule[]}

export const deployRules: DeployRules = {
  localhost: [
    {
      name: 'parser',
      contracts: [
        { name: 'Utf8', addressSrc: 'fixed' },
        { name: 'MeasureGas', addressSrc: 'fixed' },
        { name: 'Log', addressSrc: 'fixed' },
        {
          name: 'JsDocParser',
          addressSrc: 'dynamic',
          proxy: {
            contract: {
              name: 'JsDocParserProxy',
              args: [
                { address: { name: 'JsDocParser', addressSrc: 'fixed' }},
                { address: { name: 'owner', addressSrc: 'fixed' }},
                { value: utils.toUtf8Bytes('') },
              ],
              addressSrc: 'fixed'
            },
            addressSrc: 'fixed'
          }
        },
      ]
    }
  ],
  goerli: [
  ]
}