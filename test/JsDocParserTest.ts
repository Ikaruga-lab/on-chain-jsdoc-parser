import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import measureAbi from '../artifacts/contracts/MeasureGas.sol/MeasureGas'
import { addresses } from '../scripts/addresses'

describe('JsDocParserTest', function () {
  const gasLimit = 10000000
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
  it('description_3', async function () {
    const code = `/** a
b
**/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].description).to.equal(`a
b
`);
  })
  it('description_4', async function () {
    const code = `/** ab
* c
*d
e
f*
*g*
**h*
** i *
**/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].description).to.equal(`ab
c
d
e
f*
g*
*h*
* i *
`);
  })
  it('description_5', async function () {
    const code = `/** @ ss */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(1);
    expect(result[0].description).to.equal(`@ ss `);
  })
  it('description_6', async function () {
    const code = `/** @ ss
* @ gg
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`@ ss
@ gg`);
  })
  it('description_7', async function () {
    const code = `/** This is a description.
* This is other description.
* This is a description too.
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`This is a description.
This is other description.
This is a description too.`);
  })
  it('description_8', async function () {
    const code = `/**@ */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal('@ ');
  })
  it('description_9', async function () {
    const code = `/** s
* @g
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`s`);
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('g');
  })
  it('description_10', async function () {
    const code = `/**
* this is desc
* second desc
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`this is desc
second desc`);
  })
  it('description_11', async function () {
    const code = `/**
* t
*
* s
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`t

s`);
  })
  it('description_11', async function () {
    const code = `/**
* t

* s
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`t

s`);
  })
  it('tagName_1', async function () {
    const code = `/**@tag*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
  })
  it('tagName_2', async function () {
    const code = `/**@tag
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
  })
  it('tagName_3', async function () {
    const code = `/**@tag d*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
  })
  it('tagName_4', async function () {
    const code = `/**@ta*@g d*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('ta*@g');
  })
  it('tagName_5', async function () {
    const code = `/**
* @tag
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
  })
  it('tagName_6', async function () {
    const code = `/** desc
 @tag
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].description).to.equal('desc');
  })
  it('tagName_7', async function () {
    const code = `/**
 @tag
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].description).to.equal('');
  })
  it('tagName_8', async function () {
    const code = `/** @tag
 @tag2
 * @tag3
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(3);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[1].tagName).to.equal('tag2');
    expect(result[0].tags[2].tagName).to.equal('tag3');
  })
  it('paramType_1', async function () {
    const code = `/** @tag {type}*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
  })
  it('paramType_2', async function () {
    const code = `/** @tag {typ
e}*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
  })
  it('paramType_3', async function () {
    const code = `/** @tag {type}
    * @tag2 {type 2}
    */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(2);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[1].tagName).to.equal('tag2');
    expect(result[0].tags[1].paramType).to.equal('type 2');
  })
  it('paramType_4', async function () {
    const code = `/** @tag {  ty pe   }*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('ty pe');
  })
  it('paramType_5', async function () {
    const code = `/** @tag {type desc */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type desc ');
    expect(result[0].tags[0].paramDesc).to.equal('');
    expect(result[0].tags[0].paramDesc).to.equal('');
  })
  it('paramName_1', async function () {
    const code = `/** @tag {type} name*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
  })
  it('paramName_2', async function () {
    const code = `/** @tag {type} @name*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('@name');
  })
  it('paramName_3', async function () {
    const code = `/** @tag {type} {name} */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('{name}');
  })
  it('paramName_4', async function () {
    const code = `/** @tag {type} nam
e*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('nam');
  })
  it('paramName_5', async function () {
    const code = `/** @tag {type}
e*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('');
    expect(result[0].tags[0].paramDesc).to.equal('e');
  })
  it('paramDesc_1', async function () {
    const code = `/** @tag {type} name desc */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal('desc');
  })
  it('paramDesc_2', async function () {
    const code = `/** @tag {type} name
desc */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal('desc');
  })
  it('paramDesc_3', async function () {
    const code = `/** @tag {type} name d
esc
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`d
esc`);
  })
  it('paramDesc_4', async function () {
    const code = `/** @tag {type} name d
* esc
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`d
esc`);
  })
  it('paramDesc_5', async function () {
    const code = `/** @tag {type} name d
**esc
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`d
*esc`);
  })
  it('paramDesc_6', async function () {
    const code = `/** @tag {type} name d

esc
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`d

esc`);
  })
  it('paramDesc_7', async function () {
    const code = `/** @tag {type} name d
@ gg
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`d
@ gg`);
  })
  it('paramDesc_8', async function () {
    const code = `/** @tag {type} name d
@ gg
@esc
* @tag*3 name2
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].tags.length).to.equal(3);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`d
@ gg`);
    expect(result[0].tags[1].tagName).to.equal('esc');
    expect(result[0].tags[1].paramType).to.equal('');
    expect(result[0].tags[1].paramName).to.equal('');
    expect(result[0].tags[1].paramDesc).to.equal('');
    expect(result[0].tags[2].tagName).to.equal('tag*3');
    expect(result[0].tags[2].paramType).to.equal('');
    expect(result[0].tags[2].paramName).to.equal('name2');
    expect(result[0].tags[2].paramDesc).to.equal('');
  })
  it('all_1', async function () {
    const code = `/** this is description.
* @tag {type} name desc
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal('this is description.');
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`desc`);
  })
  it('all_2', async function () {
    const code = `/**
* this is description.
* second line
* @tag {type} name desc
* @tag2 {type2} name2 desc2
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`this is description.
second line`);
    expect(result[0].tags.length).to.equal(2);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`desc`);
    expect(result[0].tags[1].tagName).to.equal('tag2');
    expect(result[0].tags[1].paramType).to.equal('type2');
    expect(result[0].tags[1].paramName).to.equal('name2');
    expect(result[0].tags[1].paramDesc).to.equal(`desc2`);
  })
  it('all_3', async function () {
    const code = `/** this is description.
* @tag
* @tagType {type}
* @tagName name
* @tagTypeName {type2} name2
* @tagNameDesc name3 desc
* @tagAll {type3} name4 desc2
*/`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal(`this is description.`);
    expect(result[0].tags.length).to.equal(6);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('');
    expect(result[0].tags[0].paramName).to.equal('');
    expect(result[0].tags[0].paramDesc).to.equal(``);
    expect(result[0].tags[1].tagName).to.equal('tagType');
    expect(result[0].tags[1].paramType).to.equal('type');
    expect(result[0].tags[1].paramName).to.equal('');
    expect(result[0].tags[1].paramDesc).to.equal(``);
    expect(result[0].tags[2].tagName).to.equal('tagName');
    expect(result[0].tags[2].paramType).to.equal('');
    expect(result[0].tags[2].paramName).to.equal('name');
    expect(result[0].tags[2].paramDesc).to.equal(``);
    expect(result[0].tags[3].tagName).to.equal('tagTypeName');
    expect(result[0].tags[3].paramType).to.equal('type2');
    expect(result[0].tags[3].paramName).to.equal('name2');
    expect(result[0].tags[3].paramDesc).to.equal(``);
    expect(result[0].tags[4].tagName).to.equal('tagNameDesc');
    expect(result[0].tags[4].paramType).to.equal('');
    expect(result[0].tags[4].paramName).to.equal('name3');
    expect(result[0].tags[4].paramDesc).to.equal(`desc`);
    expect(result[0].tags[5].tagName).to.equal('tagAll');
    expect(result[0].tags[5].paramType).to.equal('type3');
    expect(result[0].tags[5].paramName).to.equal('name4');
    expect(result[0].tags[5].paramDesc).to.equal(`desc2`);
  })
  it('all_4', async function () {
    const code = `/** this is description. @tag {type} name desc */`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result[0].description).to.equal('this is description. @tag {type} name desc ');
    expect(result[0].tags.length).to.equal(0);
  })
  it('multi_comment', async function () {
    const code = `/**
* this is description.
* @tag {type} name desc
*/
class A {
  /**
  * this is description2.
  * @tag2 {type2} name2 desc2
  */
  function s() {
    /**
    * this is description3.
    * @tag3 {type3} name3 desc3
    */
  }
}
`
    const { result, gas } = await parse(code)
    gasTotal += gas;
    expect(result.length).to.equal(3);
    expect(result[0].description).to.equal('this is description.');
    expect(result[0].tags.length).to.equal(1);
    expect(result[0].tags[0].tagName).to.equal('tag');
    expect(result[0].tags[0].paramType).to.equal('type');
    expect(result[0].tags[0].paramName).to.equal('name');
    expect(result[0].tags[0].paramDesc).to.equal(`desc`);
    expect(result[1].description).to.equal('this is description2.');
    expect(result[1].tags.length).to.equal(1);
    expect(result[1].tags[0].tagName).to.equal('tag2');
    expect(result[1].tags[0].paramType).to.equal('type2');
    expect(result[1].tags[0].paramName).to.equal('name2');
    expect(result[1].tags[0].paramDesc).to.equal(`desc2`);
    expect(result[2].description).to.equal('this is description3.');
    expect(result[2].tags.length).to.equal(1);
    expect(result[2].tags[0].tagName).to.equal('tag3');
    expect(result[2].tags[0].paramType).to.equal('type3');
    expect(result[2].tags[0].paramName).to.equal('name3');
    expect(result[2].tags[0].paramDesc).to.equal(`desc3`);
  })
});