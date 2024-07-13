import 'dotenv/config'
import minimist from "minimist"
import fs from 'fs'
import { connect, createDataItemSigner } from '@permaweb/aoconnect'

const jwk = JSON.parse(process.env.AR_JWK)
const { spawn, result, dryrun,message } = connect()

async function main() {
  const args = minimist(process.argv.slice(2))
  console.log(args)
  if(args.action === null) return 
  switch(args.action){
    case "withdraw":
    default:
      await message({
        process: process.env.AOLOTTO,
        tags: [
          { name:"Action", value:"OP_withdraw"}
        ],
        signer: createDataItemSigner(jwk)
      })
      .then(console.log)
      .catch(console.error);
  }
}

main()