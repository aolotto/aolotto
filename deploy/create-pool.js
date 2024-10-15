
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

async function fetchTokenInfo(token_id){
  try {
    let tags = null
    const {Messages} = await dryrun({
      process: token_id,
      data: '',
      tags: [{name: 'Action', value: 'Info'}],
      anchor: '1234',
    });
    
    
    if(Messages&&Messages?.length>0){
      tags = {}
      Messages[0].Tags.map(item=>{
        tags[item.name] = item.value
      })
      // Object.fromEntries(Messages[0].Tags.map(item => tags[item.name] = item.value))
    }
    return tags
    
  } catch (error) {
    throw(error)
  }
  
}

async function main() {

  try{
    let agent = process.env.AOLOTTO_AGENT
    let timer = process.env.AOLOTTO_TIMER
    let {name, wallet,token,module,digists,file} = minimist(process.argv.slice(2))
    if(!token) throw("missed token address!")
    console.log("Create a pool ...")
    if(wallet){
      const jwk_str = await fs.readFileSync(wallet,'utf-8')
      jwk = JSON.parse(jwk_str)
    }else{
      jwk = JSON.parse(process.env.AR_JWK)
    }

    fetchPools(agent).then(async pools=>{

      const pool = pools[token]
      if(pool) throw("the pool for " + token + " has been created!")
      const token_tags = await fetchTokenInfo(token)
      if(!token_tags) throw("can not read token info!")
      name = name || token_tags.Ticker
      digists = digists?toString(digists):"3"
      const tags = []
      tags.push({name: "Name", value: name})
      tags.push({name: "Agent", value: agent})
      tags.push({name: "Timer", value: timer})
      tags.push({name: "Token", value: token})
      tags.push({name: "Ticker", value: token_tags.Ticker})
      tags.push({name: "Denomination", value: token_tags.Denomination})
      tags.push({name: "Logo", value: token_tags.Logo})
      tags.push({name: "Digits", value: digists})
      tags.push({name:'Content-Type',value: "text/html"})
      tags.push({name:'Authority',value: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY"})
      tags.push({name:'aos-Version',value:"2.0.0"})

     
      const spawned_process = await spawn({
        module: module || "bkjb55i07GUCUSWROtKK4HU1mBS_X0TyH3M5jMV6aPg",
        scheduler: "_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA",
        signer: createDataItemSigner(jwk),
        tags: tags,
        data: `
         <!DOCTYPE html>
          <html>
            <head>
              <meta charset="UTF-8">
              <title>Aolotto Pool™</title>
            </head>
            <body>
              A decentralized lottry pool permanently running on AO ,id: ${token}
            </body>
          </html>
        `
      });
      
      if(!spawned_process) throw("spawn process faild.")
      console.log("● Pool process: "+spawned_process)

      const msgid = await message({
        process: agent,
        signer: createDataItemSigner(jwk),
        tags: [
          {name: "Action",value: "Create-Pool"},
          {name:"Token",value:token},
          {name:"Pool",value:spawned_process},
          {name:"Name",value:name},
          {name:"Digits",value:digists},
          {name: "Ticker", value: token_tags.Ticker},
          {name: "Denomination", value: token_tags.Denomination},
          {name: "Logo", value: token_tags.Logo}
        ]
      })
      if(!msgid) throw("create request faild.")
      console.log("● Registe pool on agent: ",msgid)

      const {Messages} = await result({
        message:msgid,
        process:agent
      })

      if(!Messages||Messages?.length<1) throw("create pool error!")
      console.log("|- Registed!")

      const msgid2 = await message({
        process: timer,
        signer: createDataItemSigner(jwk),
        tags: [
          {name: "Action",value: "Add-Subscriber"},
          {name: "Subscriber",value: spawned_process}
        ]
      })

      if(!msgid) throw("registed timer faild.")
      console.log("● Add pool as a subscriber on timer: ",msgid)

      const timer_result = await result({
        message:msgid2,
        process:timer
      })

      if(!timer_result?.Messages||timer_result?.Messages?.length<1) throw("create timer error!")

      console.log("|- Added!")


      let filePath = file || "pool.lua"
      
      if (fs.existsSync(filePath)) {
        const projectStructure = await createProjectStructure(filePath)
        const [executable, modules] = createExecutableFromProject(projectStructure)
        const msgid3 = await message({
          process: spawned_process,
          data: executable,
          tags: [{
            name: "Action",
            value: "Eval"
          }],
          signer: createDataItemSigner(jwk)
        })
        if(!msgid3) throw("eval error")
        console.log("|- init process: "+ msgid3)

      }
      
  
      console.log("🎉 Done: "+spawned_process)


      

      // readLuaFile("pool.lua").then(async source=>{
      //   const msgid = await message({
      //     process: spawned_process,
      //     data: source,
      //     tags: [{
      //       name: "Action",
      //       value: "Eval"
      //     }],
      //     signer: createDataItemSigner(jwk)
      //   })
      //   console.log("inited pool: "+msgid)
      // })

    })

  }catch(err){
    console.error("FAILD:",err)
  }

}

main()