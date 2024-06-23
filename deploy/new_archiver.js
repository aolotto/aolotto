import { connect, createDataItemSigner } from '@permaweb/aoconnect'
import fs from 'fs'
import crypto from 'crypto'
const keyfile = fs.readFileSync("wallet.json","utf-8")
const jwk = JSON.parse(keyfile)


async function createProcess({name,module,tags}){
  const { spawn, result } = connect()
  tags = tags || []
  tags.push({name: "Name", value: "Archiver" })
  tags.push({name: "Agent", value: "Archiver" })
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
  console.log("创建新的Archiver进程")
}


main()