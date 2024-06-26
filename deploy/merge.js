import { promises as fs } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function mergeLuaFiles(mainFilePath) {
  let content = await fs.readFile(mainFilePath, 'utf8');
  const dir = path.dirname(mainFilePath);

  // 使用正则表达式匹配 require 语句
  const requirePattern = /require\s*\(\s*['"](.+)['"]\s*\)/g;
  const matches = content.matchAll(requirePattern);

  for (const match of matches) {
    let requiredFile = match[1];
    // 将点号转换为斜杠，但保留文件扩展名中的点号
    requiredFile = requiredFile.replace(/\./g, '/').replace(/\/(\w+)$/, '.$1');
    
    // 如果文件名没有 .lua 扩展名，添加它
    if (!requiredFile.endsWith('.lua')) {
      requiredFile += '.lua';
    }

    const fullPath = path.join(dir, requiredFile);
    
    try {
      const requiredContent = await fs.readFile(fullPath, 'utf8');
      // 将 require 语句替换为文件内容
      content = content.replace(match[0], requiredContent);
    } catch (err) {
      console.error(`Error reading file ${fullPath}: ${err.message}`);
    }
  }

  return content;
}

// 使用示例
const mainFilePath = path.join(__dirname, 'path', 'to', 'main.lua');

try {
  const mergedContent = await mergeLuaFiles(mainFilePath);
  console.log(mergedContent);
} catch (err) {
  console.error(err);
}

export { mergeLuaFiles };
