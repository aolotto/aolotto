import {mergeLuaFiles} from "./merge.js"

mergeLuaFiles('main.lua')
  .then(mergedContent => console.log(mergedContent))
  .catch(err => console.error(err));