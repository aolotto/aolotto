import { connect, createDataItemSigner } from '@permaweb/aoconnect'
import fs from 'fs'
import crypto from 'crypto'
const keyfile = fs.readFileSync("wallet.json","utf-8")
const jwk = JSON.parse(keyfile)





async function main() {
  console.log("创建新的Archiver进程")
  const { spawn, result } = connect()
  tags = tags || []
  tags.push({name: "Name", value: "Archiver" })
  tags.push({name: "Agent", value: "Archiver" })
  tags.push({name: "App-Name", value : "aolotto" })
  const process = await spawn({
    module: "cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk",
    scheduler: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",
    signer: createDataItemSigner(jwk),
    tags: tags
  });
  console.log("Spawaned Archiver: "+process)
}


main()