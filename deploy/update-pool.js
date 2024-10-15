
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
      tags: [{name: 'Action', value: 'All-Pools'}],
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
    let {wallet,file} = minimist(process.argv.slice(2))
    let filePath = file || "pool.lua"
    console.log("Files:")
    if (!fs.existsSync(filePath)) {
      throw Error('ERROR (200): file not found.');
    }
    const projectStructure = await createProjectStructure(filePath)

    const [executable, modules] = createExecutableFromProject(projectStructure)
    for(const module of modules){
      console.log("└── "+module.path + (!module.name?' - \u001b[32m*\u001b[0m':''))
    }


    if(wallet){
      const jwk_str = await fs.readFileSync(wallet,'utf-8')
      jwk = JSON.parse(jwk_str)
    }else{
      jwk = JSON.parse(process.env.AR_JWK)
    }

    fetchPools(agent).then(async(pools)=>{
      if(pools?.length<1) throw("no pools to eval")
      let count = 0
      for (var pool in pools) {
        if(pools[pool]?.pool_id){
          count = count+1
          const pid = pools[pool]?.pool_id
          console.log("\n\u001b[90m-> Pool "+count+'\u001b[0m')
          console.log("● process: "+pid)

          const msgid = await message({
            process: pid,
            tags: [{name:"Action",value:"Eval"}],
            data: executable,
            signer: createDataItemSigner(jwk)
          })
          if(!msgid) throw("eval error")
          console.log("● message: "+msgid)
          const res = await result({
            message: msgid,
            process: pid
          })
          if(!res?.Messages.length<1 && !res?.Messages[0]) throw("Eval faild.")
            console.log("● Done")

        }
      }
      console.log("\n\u001b[32m 🎉 Successfully loaded into "+count + (count>1?" pools":" pool") + '\u001b[0m')
    })
  }catch(err){
    console.error("FAILD:",err)
  }

}

main()