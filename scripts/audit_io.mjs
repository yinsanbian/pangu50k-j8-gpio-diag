import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const map=JSON.parse(await fs.readFile(path.join(root,'constraints','j8_pins.json'),'utf8'));
const pcfFile=path.join(root,'pds','device_map','gpio_diag_top.pcf');
const pcf=await fs.readFile(pcfFile,'utf8');
const ports=new Map();
const errors=[];
for (const line of pcf.split(/\r?\n/)) {
  const match=line.match(/^def_port\s+\{([^}]+)\}\s+(.+)$/);
  if (!match) continue;
  if (ports.has(match[1])) errors.push(`Duplicate PCF port ${match[1]}`);
  ports.set(match[1],Object.fromEntries([...match[2].matchAll(/([A-Z_]+)=(\S+)/g)].map(m=>[m[1],m[2]])));
}
const wanted=[...map.fixed,...map.gpio.map((row,index)=>({...row,port:`j8_gpio[${index}]`,direction:'INOUT'}))];
const rows=[];
for (const row of wanted) {
  const actual=ports.get(row.port);
  const expected={LOC:row.pin,VCCIO:'3.3',IOSTANDARD:'LVCMOS33',NONE:'TRUE',
    ...(row.direction==='INPUT'?{}:{DRIVE:'4',SLEW:'SLOW'})};
  const failures=Object.entries(expected).filter(([name,value])=>actual?.[name]!==value).map(([name,value])=>`${name}: wanted ${value}, actual ${actual?.[name]}`);
  if (failures.length) errors.push(`${row.port}: ${failures.join('; ')}`);
  rows.push({port:row.port,j8:row.j8??null,pin:row.pin,direction:row.direction,ok:failures.length===0,actual});
}
if (ports.size!==38) errors.push(`Expected 38 ports, got ${ports.size}`);
const assigned=[...ports.values()].map(row=>row.LOC);
if (new Set(assigned).size!==38) errors.push('Duplicate physical pin assignment');
const snrFile=path.join(root,'pds','synthesize','gpio_diag_top.snr');
const snr=await fs.readFile(snrFile,'utf8');
const ioBuffers=Number(snr.match(/^GTP_IOBUF\s+(\d+)\s+uses/m)?.[1]??-1);
if (ioBuffers!==34) errors.push(`Expected 34 GTP_IOBUF, got ${ioBuffers}`);
const ccrFile=path.join(root,'pds','synthesize','constraint_check.ccr');
const ccr=await fs.readFile(ccrFile,'utf8');
if (!/Found 0 error\(s\), 0 critical warning\(s\)/.test(ccr)) errors.push('Constraint check has errors or critical warnings');
if (!ccr.includes('i:u_ctrl/rx_meta[33:0]')) errors.push('GPIO first synchronizer stage was not positively matched');
const result={ok:errors.length===0,ports:ports.size,gpioIOBuffers:ioBuffers,errors,pcfFile,snrFile,ccrFile,rows};
await fs.mkdir(path.join(root,'reports'),{recursive:true});
await fs.writeFile(path.join(root,'reports','io_audit.json'),JSON.stringify(result,null,2)+'\n');
const displayPath=file=>path.relative(root,file).replaceAll('\\','/');
const md=['# PDS IO 映射逐脚审计','',`结果：${result.ok?'PASS':'FAIL'}；38 个物理端口，${ioBuffers} 个 GTP_IOBUF。`,
  '',`生成 PCF：${displayPath(pcfFile)}`,`综合报告：${displayPath(snrFile)}`,`约束检查：${displayPath(ccrFile)}`,'',
  '| 端口 | J8物理脚 | 封装脚 | 方向 | IO标准 | 结果 |','|---|---:|---|---|---|---|',
  ...rows.map(row=>`| ${row.port} | ${row.j8??'—'} | ${row.pin} | ${row.direction} | ${row.actual?.IOSTANDARD??'missing'} | ${row.ok?'PASS':'FAIL'} |`),'',
  '内部偏置 NONE=TRUE；所有输出和双向端口均 DRIVE=4、SLEW=SLOW；没有重复占用封装脚。',
  'GPIO 输入异常例外匹配到第一同步级 u_ctrl/rx_meta[33:0]，并保留后级 50 MHz 时序检查。',
  ...errors.map(error=>`- ${error}`),''];
await fs.writeFile(path.join(root,'reports','io_audit.md'),md.join('\n'));
console.log(JSON.stringify({ok:result.ok,ports:result.ports,gpioIOBuffers:ioBuffers,errors},null,2));
if(!result.ok)process.exitCode=1;
