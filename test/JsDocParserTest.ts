import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import measureAbi from '../artifacts/contracts/MeasureGas.sol/MeasureGas'
import { addresses } from '../scripts/addresses'

describe('JsDocParserTest', function () {
  const gasLimit = 1000000
  const proxyAddress = addresses['localhost']['parser']['JsDocParserProxy']
  const measuerAddress = addresses['localhost']['parser']['MeasureGas']

  async function deployFixture() {
    const provider = new ethers.providers.JsonRpcProvider('http://127.0.0.1:8545/')
    return new ethers.Contract(
      measuerAddress,
      measureAbi.abi,
      provider
    )
  }

  async function parse(code: string) {
    const measure = await loadFixture(deployFixture);
    const res = await measure.measure(proxyAddress, code, { gasLimit: gasLimit })
    return { result: res[1], gas: +res[0] }
  } 
  
  let gasTotal = 0

  before(async function() {
    await loadFixture(deployFixture);
  });

  after(async function() {
    console.log(`GAS TOTAL: ${gasTotal}`)
  })
  
  it('empty', async function () {
    const code = `/** */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].description).to.equal('');
  })
  it('empty_2', async function () {
    const code = `/**
*
 */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].lines.length).to.equal(3);
    expect(result[0].lines[0].rawExpression).to.equal('/**');
    expect(result[0].lines[1].rawExpression).to.equal('*');
    expect(result[0].lines[2].rawExpression).to.equal(' */');
    expect(result[0].description).to.equal('');
  })
  it('description_1', async function () {
    const code = `/**a*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].description).to.equal('a');
  })
  it('description_2', async function () {
    const code = `/** *a**/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].description).to.equal('*a*');
  })
  it('tagName_1', async function () {
    const code = `/**@ */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].description).to.equal('*a');
  })
});