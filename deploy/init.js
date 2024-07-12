import 'dotenv/config'
import minimist from "minimist"
import fs from 'fs'
import { connect, createDataItemSigner } from '@permaweb/aoconnect'

const jwk = JSON.parse(process.env.AR_JWK)
const { spawn, result, dryrun } = connect()


// 创建进程
// async function createProcess({name,module,tags}){
//   const { spawn, result } = connect()
//   tags = tags || []
//   tags.push({name: "Name", value: name || "test" })
//   tags.push({name: "App-Name", value : "aolotto" })
//   const process = await spawn({
//     module: module || "GYrbbe0VbHim_7Hi6zrOpHQXrSQz07XNtwCnfbFo2I0",
//     scheduler: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY",
//     signer: createDataItemSigner(jwk),
//     tags: tags
//   });
//   console.log("Spawaned ["+name+"]:"+process)
//   return process
// }

async function main() {
  const args = minimist(process.argv.slice(2))
  const tags = []
  switch(args['type']){
    case "lottery":
    default:
      console.log("create a lottery process.")
      const token_process = args['token'] || 'zQ0DmjTbCEGNoJRcjdwdZTHt0UBorTeWbb_dnc6g41E'
      const result = await dryrun({
        process: token_process,
        data: '',
        tags: [{name: 'Action', value: 'Info'}],
        anchor: '1234',
      });
      const token = Object.fromEntries(result.Messages[0].Tags.map(item => [item.name, item.value]))
      token.process = token_process

      tags.push({name: "Name", value: args['name'] || "lottery" })
      tags.push({name: "App-Name", value : "aolotto" })
      tags.push({name: "Cron-Interval",value: "2-minutes" })
      tags.push({name: "Cron-Tag-Action",value: "Cron" })
      tags.push({name: "Token",value: token_process })
      tags.push({name: "Ticker",value: token.Ticker })
      tags.push({name: "Denomination",value: token.Denomination })
      tags.push({name: "Tokenname",value: token.Name })

      const process = await spawn({
        module: args['module'] || "u1Ju_X8jiuq4rX9Nh-ZGRQuYQZgV2MKLMT3CZsykk54",
        scheduler: "_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA",
        signer: createDataItemSigner(jwk),
        tags: tags
      });
      console.log("Spawaned a lottery process: "+process)

      const packageJSON = fs.readFileSync('package.json', 'utf-8')
      const packageData = JSON.parse(packageJSON)
      packageData.scripts["aolotto"]= `aos ${process} --wallet wallet.json`
       fs.writeFile('package.json', JSON.stringify(packageData,null,"\t"), (err) => {
        if (err) {
            throw err;
        }
        console.log("`npm run aolotto` to start process.");
      });
  }
  
  // const uuid = crypto.randomUUID()
  // const name = process.env.APP_NAME || "aolotto"
  // const tags = []
  // tags.push({ name: "App-Id", value: uuid })
  // if(process.env.APP_OPERATOR){
  //   tags.push[{name: "Operator", value: process.env.APP_OPERATOR}]
  // }
  // const process = await createProcess({name,tags,module:process.env.AOS_MOUDULE,data: process.env.APP_DATA})
  // // const SHOOTER = await createProcess({
  // //   name:"SHOOTER",
  // //   module:"1PdCJiXhNafpJbvC-sjxWTeNzbf9Q_RfUNs84GYoPm0",
  // //   tags:[{
  // //     name:"App-Id",value:uuid
  // //   },{
  // //     name:"Cron-Interval",value: "5-minutes"
  // //   },{
  // //     name:"Cron-Tag-Action",value: "Cron"
  // //   }]
  // // })
  // // const OPERATOR = await createProcess({
  // //   name:"OPERATOR",
  // //   module:"1PdCJiXhNafpJbvC-sjxWTeNzbf9Q_RfUNs84GYoPm0",
  // //   tags:[{name:"App-Id",value:uuid}]
  // // })

  // const lua_config =  `
  //   local config = {}
  //   config.AGENT = "${AGENT}"
  //   config.SHOOTER = "${SHOOTER}"
  //   config.OPERATOR = "${OPERATOR}"
  //   return config
  // `

  // fs.writeFile('_config.lua', lua_config, (err) => {
  //   if (err) {
  //       throw err;
  //   }
  //   console.log("All process is spawned.");
  // });

  // fs.writeFile('deploy/'+uuid+'.txt', lua_config, (err) => {
  //   if (err) {
  //       throw err;
  //   }
  //   console.log("spawned is logged.");
  // });

  // const packageJSON = fs.readFileSync('package.json', 'utf-8')
  // const packageData = JSON.parse(packageJSON)
  // packageData.scripts["AGENT"]= `aos ${AGENT} --wallet wallet.json`
  // packageData.scripts["SHOOTER"]= `aos ${SHOOTER} --wallet wallet.json`
  // packageData.scripts["ARCHIVER"]= `aos ${ARCHIVER} --wallet wallet.json`
  // packageData.scripts["OPERATOR"]= `aos ${OPERATOR} --wallet wallet.json`
  //  fs.writeFile('package.json', JSON.stringify(packageData,null,"\t"), (err) => {
  //   if (err) {
  //       throw err;
  //   }
  //   console.log("changed package.json.");
  // });
  

}


main()