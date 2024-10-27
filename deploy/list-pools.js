
import minimist from "minimist"
import fs from 'fs'
import path from 'path'
import { connect, createDataItemSigner } from '@permaweb/aoconnect'
import { createProjectStructure,createExecutableFromProject } from './loading-files.js'


let jwk
const { spawn, result, dryrun,message } = connect({
  MU_URL: "https://mu.ao-testnet.xyz",
  CU_URL: "https://cu.ao-testnet.xyz",
  GATEWAY_URL: "https://arweave.net",
})


async function fetchPools(agent_id){
  try {
    let data = []
    const {Messages} = await dryrun({
      process: agent_id,
      data: '',
      tags: [{name: 'Action', value: 'Pools'}],
      anchor: '1234',
    });
    
    if(Messages&&Messages?.length>0){
      data = JSON.parse(Messages[0].Data)
    }
    return data
    
  } catch (error) {
    throw(error)
  }
}



async function main() {

  try{
    let agent = process.env.AOLOTTO_AGENT
    console.log(`\u001b[90mLoading Pools on ${agent} ...\u001b[0m`)
    fetchPools(agent).then(async(pools)=>{
      
      for(const pool in pools){
        console.log(`* \u001b[33m${pools[pool].ticker.padEnd(5)}\u001b[0m` + " -> " + pools[pool].pool_id + `\u001b[90m - ${pool}\u001b[0m` + ` - ${pools[pool].state === 1?'●':'○'}`)
      }

      if(!pools||pools.length<1){
        console.log("No pool exists")
      }
      
    })
  }catch(err){
    console.error("FAILD:",err)
  }

}

main()