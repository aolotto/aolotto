import minimist from "minimist"
async function main() {
  let args = minimist(process.argv.slice(2))
  console.log(args)
}

main()