import 'dotenv/config'
import minimist from "minimist"
import fs from 'fs'
import { connect, createDataItemSigner } from '@permaweb/aoconnect'

const jwk = JSON.parse(process.env.AR_JWK)
const { spawn, result, dryrun } = connect()

async function fetchTokenInfo(pid){
  const result = await dryrun({
    process: pid,
    data: '',
    tags: [{name: 'Action', value: 'Info'}],
    anchor: '1234',
  });
  const token = Object.fromEntries(result.Messages[0].Tags.map(item => [item.name, item.value]))
  token.process = pid
  return token
}


async function main() {
  const args = minimist(process.argv.slice(2))
  console.log(args)
  console.log(`create a [${args.type||'lottery'}] process.`)
  const tags = []
  const token_process = args['token'] || 'zQ0DmjTbCEGNoJRcjdwdZTHt0UBorTeWbb_dnc6g41E'
  const token = await fetchTokenInfo(token_process)
  tags.push({name: "App-Name", value : args['name'] || "aolotto" })
  tags.push({name: "Token",value: token_process })
  tags.push({name: "Ticker",value: token.Ticker })
  tags.push({name: "Denomination",value: token.Denomination })
  tags.push({name: "Tokenname",value: token.Name })
  // const aoprocess = null
  switch(args['type']){
    case "archiver":
      tags.push({name: "Name", value: args['type'] || "archiver" })
      if(args['lottery']){
        tags.push({name: "Lottery", value: args['lottery'] })
        tags.push({name: "Round", value: args['round'] || '' })
        const aoprocess = await spawn({
          module: args['module'] || "Pq2Zftrqut0hdisH_MC2pDOT6S4eQFoxGsFUzR6r350",
          scheduler: "_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA",
          signer: createDataItemSigner(jwk),
          tags: tags
        });
        console.log("Spawaned: "+aoprocess)
      }
      break;
    case "lottery":
    default:
      tags.push({name: "Name", value: args['type'] || "lottery" })
      tags.push({name: "Cron-Interval",value: "2-minutes" })
      tags.push({name: "Cron-Tag-Action",value: "Cron" })
      
      const aoprocess = await spawn({
        module: args['module'] || "u1Ju_X8jiuq4rX9Nh-ZGRQuYQZgV2MKLMT3CZsykk54", // sqlite 64
        scheduler: "_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA",
        signer: createDataItemSigner(jwk),
        tags: tags
      });
      console.log("Spawaned: "+aoprocess)

      const packageJSON = fs.readFileSync('package.json', 'utf-8')
      const packageData = JSON.parse(packageJSON)
      packageData.scripts["aolotto"]= `aos ${aoprocess} --wallet wallet.json`
       fs.writeFile('package.json', JSON.stringify(packageData,null,"\t"), (err) => {
        if (err) {
            throw err;
        }
        console.log("`npm run aolotto` to start process.");
      });
      break;
  }
}


main()