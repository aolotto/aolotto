// Deploy to AO
import { connect, createDataItemSigner } from '@permaweb/aoconnect'
import fs from 'fs'
import crypto from 'crypto'


const lua = fs.readFileSync('main.lua', 'utf-8')
const keyfile = fs.readFileSync("wallet.json","utf-8")
const jwk = JSON.parse(keyfile)




async function evaluate() {
  const { message, result } = connect()

  const messageId = await message({
    process: AOS,
    signer: createDataItemSigner(jwk),
    tags: [
      { name: 'Action', value: 'Eval' }
    ],
    data: lua
  })

  const res = await result({
    process: AOS,
    message: messageId
  })

  if (res?.Output?.data) {
    console.log('Successfully published AOS process ', messageId)
  } else {
    console.error(res?.Error || 'Unknown error occured deploying AOS')
  }
}

async function createProcess({name,module,tags}){
  const { spawn, result } = connect()
  tags = tags || []
  tags.push({name: "Name", value: name || "test" })
  tags.push({name: "App-Name", value : "aolotto" })
  const process = await spawn({
    module: module || "GYrbbe0VbHim_7Hi6zrOpHQXrSQz07XNtwCnfbFo2I0",
    scheduler: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",
    signer: createDataItemSigner(jwk),
    tags: tags
  });
  console.log("Spawaned ["+name+"]:"+process)
  return process
}


async function main() {

  // "go": "aos d07Mw0sRbtTB8sz1-t0zSGcRS6YK_q11nsx7h6dOuzg --wallet wallet.json",

  
  let uuid = crypto.randomUUID();
  const AGENT = await createProcess({
    name:"AGENT",
    tags:[{name:"App-Id",value:uuid}]
  })
  const ARCHIVER = await createProcess({
    name:"ARCHIVER",
    tags:[{name:"App-Id",value:uuid}]
  })
  const SHOOTER = await createProcess({
    name:"SHOOTER",
    module:"1PdCJiXhNafpJbvC-sjxWTeNzbf9Q_RfUNs84GYoPm0",
    tags:[{
      name:"App-Id",value:uuid
    },{
      name:"Cron-Interval",value: "5-minutes"
    },{
      name:"Cron-Tag-Action",value: "Cron"
    }]
  })
  const OPERATOR = await createProcess({
    name:"OPERATOR",
    module:"1PdCJiXhNafpJbvC-sjxWTeNzbf9Q_RfUNs84GYoPm0",
    tags:[{name:"App-Id",value:uuid}]
  })

  const lua_config =  `
    local config = {}
    config.AGENT = "${AGENT}"
    config.SHOOTER = "${SHOOTER}"
    config.ARCHIVER = "${ARCHIVER}"
    config.OPERATOR = "${OPERATOR}"
    return config
  `

  fs.writeFile('_config.lua', lua_config, (err) => {
    if (err) {
        throw err;
    }
    console.log("All process is spawned.");
  });

  fs.writeFile('deploy/'+uuid+'.txt', lua_config, (err) => {
    if (err) {
        throw err;
    }
    console.log("spawned is logged.");
  });

  const packageJSON = fs.readFileSync('package.json', 'utf-8')
  const packageData = JSON.parse(packageJSON)
  packageData.scripts["AGENT"]= `aos ${AGENT} --wallet wallet.json`
  packageData.scripts["SHOOTER"]= `aos ${SHOOTER} --wallet wallet.json`
  packageData.scripts["ARCHIVER"]= `aos ${ARCHIVER} --wallet wallet.json`
  packageData.scripts["OPERATOR"]= `aos ${OPERATOR} --wallet wallet.json`
   fs.writeFile('package.json', JSON.stringify(packageData,null,"\t"), (err) => {
    if (err) {
        throw err;
    }
    console.log("changed package.json.");
  });
  

}


main()
// console.log("dddddd")
