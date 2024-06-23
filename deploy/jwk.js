import fs from 'fs'
const keyfile = fs.readFileSync("wallet.json","utf-8")
const jwk = JSON.parse(keyfile)

export default jwk