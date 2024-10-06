local function moduleToString(modulePath)
  -- 尝试加载文件但不执行
  local loadedModule, errorMsg = loadfile(modulePath)
  if not loadedModule then
    print("加载模块失败: " .. errorMsg)
    return nil
  end
  
  -- 将加载的函数转换为二进制字符串
  local binaryString = string.dump(loadedModule)
  
  -- 尝试读取源文件内容（如果需要可读的源代码）
  local sourceString
  local file = io.open(modulePath, "r")
  if file then
    sourceString = file:read("*all")
    file:close()
  else
    print("无法打开源文件进行读取")
  end
  
  return {
    binary = binaryString,
    source = sourceString
  }
end

SOURCE_CODE = moduleToString("pool2.lua")

print(SOURCE_CODE.source)