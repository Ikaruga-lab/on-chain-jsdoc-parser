import { task, types } from 'hardhat/config'
import { constants, Contract, ContractInterface } from 'ethers';
import { addresses } from '../scripts/addresses'
import { deployRules, ArgRule, ContractRule, AddressSrc } from '../scripts/deployRules'

task('deploy', 'Deploy contracts')
  .addOptionalParam('estimateGasOnly', 'do not deploy. just estimate deployment gas', false, types.boolean)
  .addOptionalParam('forceDeploy', 'force deoloy even if addressSrc is fixed', false, types.boolean)
  .setAction(async (taskArgs, { ethers, network, run }) => {

    const [owner, admin] = await ethers.getSigners()

    console.log(`Network: ${network.name}`)
    console.log(`Owner Address: ${owner.address}`)
    console.log(`Owner Balance: ${ethers.utils.formatEther(await owner.getBalance())}`)
    console.log(`Admin Address: ${admin.address}`)
    console.log(`Admin Balance: ${ethers.utils.formatEther(await admin.getBalance())}`)
    const gasPrice = await owner.getGasPrice();
    console.log(`Gas price: ${gasPrice}`);
    
    console.log('Compiling...')
    await run('compile')
    
    let totalCost: any = ethers.BigNumber.from(0)
    const fixedAddresses: {[key:string]:string} = {}
    for (let mod in addresses[network.name]) {
      for (let cont in addresses[network.name][mod]) {
        fixedAddresses[cont] = addresses[network.name][mod][cont]
      }
    }
    const deployedAddresses: {[key:string]:string} = { 'owner': owner.address, 'admin': admin.address }
    const deploymentCosts: {[key:string]:string} = {}

    async function estimateDeployPrice(signer: any, gasPrice: any, factory: any, args: any[]) {
      const estimatedGas = await signer.estimateGas(factory.getDeployTransaction(...args))
      return gasPrice.mul(estimatedGas);
    }

    function getAddress(contname: string, rule: AddressSrc): string | undefined {
      if (rule === 'fixed' || rule === 'external') {
        return fixedAddresses[contname]
      } else if (rule === 'dynamic') {
        return deployedAddresses[contname]
      } else if (rule === 'dummy') {
        return constants.AddressZero
      } else {
        return undefined
      }
    }

    function resolveAddressSrc(addressRule: AddressSrc): AddressSrc {
      if (taskArgs.estimateGasOnly || addressRule === 'dummy') {
        return 'dummy'
      } else if (addressRule === 'external') { // use fixed external lib address
        return 'external'
      } else if (taskArgs.forceDeploy) { // force re-deploy even if dynamic
        return 'dynamic'
      } else {
        return addressRule
      }
    }

    function getArgs(rules: ArgRule[], moduleName: string): any[] {
      const args: any = []
      rules.forEach(argRule => {
        if (argRule.address !== undefined) {
          const rule = resolveAddressSrc(argRule.address.addressSrc)
          let argAddress = getAddress(argRule.address.name, rule)
          if (argAddress === undefined || argAddress === '') {
            throw new Error(`contract ${argRule.address.name} is not deployed`)
          } 
          args.push(argAddress)
        } else if (argRule.value !== undefined) {
          args.push(argRule.value)
        }
      })
      return args
    }

    async function deployContract(contractRule: ContractRule, moduleName: string) {
      const contractSrc = resolveAddressSrc(contractRule.addressSrc)
      if (contractSrc === 'fixed') {
        const contractAddress = getAddress(contractRule.name, contractSrc)
        if (contractAddress === undefined || contractAddress === '') {
          throw new Error(`contract ${contractRule.name} is required fixed address, but not deployed`)
        }
        console.log(`  Use fixed address contract ${contractRule.name} of ${contractAddress}`)
        return
      }
      const libs: any = {}
      contractRule.libs?.forEach(libRule => {
        const rule = resolveAddressSrc(libRule.addressSrc)
        let libAddress = getAddress(libRule.name, rule)
        if (libAddress === undefined || libAddress === '') {
          throw new Error(`contract ${libRule.name} is not deployed`)
        } 
        libs[libRule.name] = libAddress
      })
      const factory = await ethers.getContractFactory(contractRule.name, { libraries: libs })
      let args: any = []
      if (contractRule.args !== undefined) {
        args = getArgs(contractRule.args, moduleName)
      }
      const cost = await estimateDeployPrice(owner, gasPrice, factory, args)
      deploymentCosts[contractRule.name] = ethers.utils.formatEther(cost)
      totalCost = totalCost.add(cost)
      if (taskArgs.estimateGasOnly) {
        deployedAddresses[contractRule.name] = constants.AddressZero
      } else {
        if (args.length > 0) {
          console.log(`  ${contractRule.name} receives args`)
          args.forEach(arg => { console.log(`    ${arg}`) })
        }
        const contract = await factory.deploy(...args)
        await contract.deployed()
        console.log(`  Deployed contract ${contractRule.name} to ${contract.address} for ${deploymentCosts[contractRule.name]} eth`)
        deployedAddresses[contractRule.name] = contract.address
        if (contractRule.proxy !== undefined) {
          const proxySrc = resolveAddressSrc(contractRule.proxy.addressSrc)
          if (proxySrc === 'dynamic') {
            console.log(`  Deploying proxy contract ${contractRule.proxy.contract.name}`)
            await deployContract(contractRule.proxy.contract, moduleName)
          } 
          const proxyAddress = getAddress(contractRule.proxy.contract.name, proxySrc)
          if (proxyAddress === undefined || proxyAddress === '') {
            throw new Error(`contract ${contractRule.proxy.contract.name} is not deployed`)
          }
          if (proxySrc === 'fixed' && contractSrc === 'dynamic') {
            // implementation is updated and set it to proxy
            console.log(`${contractRule.name} implementation is updated and set it to proxy ${contractRule.proxy.contract.name}`)
            const proxyContract = await ethers.getContractAt(contractRule.proxy.contract.name, proxyAddress)
            await proxyContract.connect(owner).upgradeTo(contract.address)
          } else if (proxySrc === 'dynamic' && contractSrc === 'dynamic') {
            if (contractRule.proxy.init !== undefined) {
              console.log(`  Initialize ${contractRule.name} via proxy contract ${contractRule.proxy.contract.name}`)
              args = getArgs(contractRule.proxy.init, moduleName)
              args.forEach(arg => { console.log(`    ${arg}`) })
              await contract.attach(proxyAddress).connect(admin).initialize(...args)
            }
          }
        }
      }
    }

    const moduleRules = deployRules[network.name]
    for (let i = 0; i < moduleRules.length; ++i) {
      const moduleRule = moduleRules[i]
        console.log(`Deploying module ${moduleRule.name}`)
      for (let j = 0; j < moduleRule.contracts.length; ++j) {
        const contractRule = moduleRule.contracts[j]
        console.log(`  Deploying contract ${contractRule.name}`)
        await deployContract(contractRule, moduleRule.name)
      }
    }
    console.log('[Addresses]')
    for (let contract in deployedAddresses) {
      console.log(`  ${contract}: '${deployedAddresses[contract]}',`)
    }
    console.log('[Deploy costs]')
    for (let contract in deploymentCosts) {
      console.log(`  ${contract}: ${deploymentCosts[contract]} eth`)
    }
    console.log(`  Total: ${ethers.utils.formatEther(totalCost)} eth`)
  })