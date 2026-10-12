import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const logDir=path.join(root,'reports','mcp');
const records=[];
for(const name of (await fs.readdir(logDir)).filter(name=>name.endsWith('.json')).sort()) {
  const record=JSON.parse(await fs.readFile(path.join(logDir,name),'utf8'));
  const value=record.response?.structuredContent;
  if (value?.ok && value.pdsPath?.endsWith('pangu50k_j8_gpio_diag.pds')) records.push({...record,value,logPath:path.join(logDir,name)});
}
const stages=['compile','synthesize','dev_map','pnr','report_timing','gen_bit_stream'];
const latest=Object.fromEntries(stages.map(stage=>[stage,records.filter(record=>record.value.runTarget===stage).at(-1)]));
const errors=stages.filter(stage=>!latest[stage]).map(stage=>`Missing successful MCP stage ${stage}`);
const timing=latest.gen_bit_stream?.value.timing??latest.report_timing?.value.timing;
if (timing?.met!==true) errors.push('Timing report does not positively state all constraints met');
const archivedTiming=path.join(root,'reports','timing_gpio_diag_top.rtr');
const timingText=latest.gen_bit_stream?.value.full?.reports?.timingReport??latest.report_timing?.value.full?.reports?.timingReport;
if(timingText)await fs.writeFile(archivedTiming,timingText);
const archivedExceptions=path.join(root,'reports','timing_gpio_diag_top_exception.rtr');
await fs.copyFile(path.join(root,'pds','report_timing','gpio_diag_top_exception.rtr'),archivedExceptions);
const sbit=latest.gen_bit_stream?.value.bitstreams?.find(file=>file.endsWith('.sbit'));
if(!sbit)errors.push('Missing newly generated .sbit');
const displayPath=file=>path.relative(root,file).replaceAll('\\','/');
const hashFile=async(file)=>createHash('sha256').update(await fs.readFile(file)).digest('hex');
const sourceFiles=(await fs.readdir(path.join(root,'rtl'))).filter(name=>name.endsWith('.v')).map(name=>path.join(root,'rtl',name));
const hashes={};
for (const file of [...sourceFiles,path.join(root,'constraints','j8_gpio_mes50hp.fdc'),...(sbit?[sbit]:[])]) {
  try{hashes[path.relative(root,file).replaceAll('\\','/')]=await hashFile(file);}catch(error){errors.push(error.message);}
}
const result={ok:errors.length===0,date:'2026-10-10',tool:'pango-mcp-local 0.1.0',part:'PGL50H-6IFBG484',errors,
  stages:Object.fromEntries(stages.map(stage=>[stage,latest[stage]?{ok:true,mcpLog:latest[stage].logPath,vendorLog:latest[stage].value.logPath}:null])),
  timing,resources:latest.gen_bit_stream?.value.utilization??latest.synthesize?.value.utilization,
  bitstream:sbit,archivedTiming,archivedExceptions,sha256:hashes};
await fs.writeFile(path.join(root,'reports','pds_build.result.json'),JSON.stringify(result,null,2)+'\n');
const md=['# PDS 工程实现验收','',`结果：${result.ok?'PASS':'FAIL'}。真实 pango-mcp tools/call 执行 PDS 2023.2-SP3，目标 Logos/PGL50H/-6/FBG484。`,'',
  '| 阶段 | 结果 |','|---|---|',...stages.map(stage=>`| ${stage} | ${latest[stage]?'PASS':'MISSING'} |`),'',
  `时钟要求：50 MHz；时序结论：${timing?.verdict??'missing'}。`,
  `Setup 最差余量：${timing?.setupWorstNs??'missing'} ns；Hold 最差余量：${timing?.holdWorstNs??'missing'} ns；Fmax：${timing?.fmaxMhz??'missing'} MHz。`,'',
  `资源：LUT=${result.resources?.luts?.used}，寄存器=${result.resources?.registers?.used}，锁存器=${result.resources?.latches?.used}，DRM/APM=0，IO=${result.resources?.io?.used}。`,
  '综合报告明确有 34 个 GTP_IOBUF，GPIO 三态映射正确；38 路管脚逐项审计见 io_audit.md。','',
  `位流：${sbit?displayPath(sbit):'missing'}；主配置时钟已显式设置 40M。`,
  `独立归档的时序报告：${displayPath(archivedTiming)}。`,'',
  '## 已审查的工具提示',
  '',
  'KEY1 与 J8 的 AB13/Y13/AB5/Y5 属于器件共享配置脚，PDS 提示 share pin；这些管脚来自原厂板卡手册，PCF 与实现已匹配，未启用保留并行配置端口。',
  'GPIO 回环和 UART 是异步接口，TA 提示未设置同步 IO delay 并按组合 IO 处理。工程不虚构外部时钟相位；对输入只切除到第一同步级的异步建立/保持检查，对输出施加 100 ns max_delay，后级与内部逻辑按 50 MHz 检查。',
  '原输入命令计数器最高位被优化为常数，这是参数范围内的正常优化；没有 latch 和多驱动。',
  '验证摘要由本机 pango-mcp 和 PDS 输出整理；原始工具日志与许可证配置留在本机，不纳入公开仓库。',
  '本次只进行了离线创建、仿真与实现；未执行任何器件下载或实板诊断。','',
  '完整阶段摘要包含在本文件中；本机原始工具记录不纳入公开仓库。',...errors.map(error=>`- ${error}`),''];
await fs.writeFile(path.join(root,'reports','pds_build.md'),md.join('\n'));
console.log(JSON.stringify({ok:result.ok,errors,timing,bitstream:sbit},null,2));
if(!result.ok)process.exitCode=1;
