import fs from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'pds');
const file = path.join(dir, 'pangu50k_j8_gpio_diag.pds');
const rtl = ['reset_sync.v','gpio_pair_mux.v','error_counter.v','gpio_test_ctrl.v',
  'uart_tx.v','uart_rx.v','diag_command.v','uart_report.v','gpio_diag_top.v'];
const status = spawnSync('tasklist.exe', ['/FI','IMAGENAME eq pds.exe','/FO','CSV','/NH'],
  {encoding:'utf8',windowsHide:true});
if (status.status !== 0 || /"pds\.exe"\s*,/i.test(status.stdout)) {
  throw new Error('PDS GUI must be closed before changing the project');
}
for (const name of rtl) await fs.access(path.join(root,'rtl',name));
await fs.access(path.join(root,'constraints','j8_gpio_mes50hp.fdc'));
let body = await fs.readFile(file,'utf8');
if (!body.includes('2023.2-SP3')) throw new Error('Unsupported project format');
function endOfNode(start) {
  let depth = 0, quoted = false, escaped = false;
  for (let index=start;index<body.length;index++) {
    const ch=body[index];
    if (escaped) {escaped=false;continue;}
    if (ch==='\\') {escaped=true;continue;}
    if (ch==='"') {quoted=!quoted;continue;}
    if (quoted) continue;
    if (ch==='(') depth++;
    if (ch===')' && --depth===0) return index+1;
  }
  throw new Error('Unbalanced project node');
}
function replaceWidget(name,text) {
  const needle=`(_widget ${name}`;
  const start=body.indexOf(needle);
  if (start<0 || body.indexOf(needle,start+needle.length)>=0) throw new Error(`Ambiguous widget ${name}`);
  body=body.slice(0,start)+text+body.slice(endOfNode(start));
}
const timespec=new Date().toISOString().slice(0,19);
const sourceLines=rtl.map(name => `                (_file "../rtl/${name}"\n                    (_format verilog)\n                    (_timespec "${timespec}")\n                    (_library "work")\n                )`).join('\n');
replaceWidget('wgt_my_design_src',`(_widget wgt_my_design_src\n            (_input\n${sourceLines}\n            )\n        )`);
replaceWidget('wgt_import_logic_con_file',`(_widget wgt_import_logic_con_file\n            (_input\n                (_file "../constraints/j8_gpio_mes50hp.fdc"\n                    (_format fdc)\n                    (_timespec "${timespec}")\n                )\n            )\n        )`);
if (!body.includes('(_option top_module')) {
  const compileStart=body.indexOf('(_command cmd_compile');
  if (compileStart<0) throw new Error('No compile command found');
  const insertAt=body.indexOf('\n',compileStart)+1;
  body=body.slice(0,insertAt)+'            (_option top_module (_string "gpio_diag_top"))\n'+body.slice(insertAt);
}
if (!body.includes('(_option master_configuration_clock_frequency')) {
  const bitStart=body.indexOf('(_command cmd_gen_bitstream');
  if (bitStart<0) throw new Error('No bitstream command found');
  const insertAt=body.indexOf('\n',bitStart)+1;
  body=body.slice(0,insertAt)+'            (_option master_configuration_clock_frequency (_string "40M"))\n'+body.slice(insertAt);
}
// fab_demo is PDS's built-in flow schema identifier, not a user project name.
body=body.replace(/\(_flow pangu50k_j8_gpio_diag /,'(_flow fab_demo ');
const stamp=new Date().toISOString().replace(/[:.]/g,'-');
const backup=path.join(dir,'.pango-mcp','project-backups',stamp);
await fs.mkdir(backup,{recursive:true});
await fs.copyFile(file,path.join(backup,path.basename(file)));
await fs.writeFile(file,body);
for (const name of ['gpio_diag_top.v','gpio_diag_top.fdc','pangu50k_j8_gpio_diag.tcl']) {
  const from=path.join(dir,name);
  try { await fs.rename(from,path.join(backup,name)); } catch(error) { if(error.code!=='ENOENT') throw error; }
}
const tcl=['# Replay with PDS 2023.2-SP3; no board programming.',
  'set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484',
  ...rtl.map(name=>`add_design {${path.join(root,'rtl',name).replaceAll('\\','/')}}`),
  `add_constraint {${path.join(root,'constraints','j8_gpio_mes50hp.fdc').replaceAll('\\','/')}}`,
  'compile -top_module gpio_diag_top','synthesize -ads -selected_syn_tool_opt 2',
  'dev_map','pnr','report_timing',
  'gen_bit_stream -master_configuration_clock_frequency {40M}',''];
await fs.writeFile(path.join(root,'scripts','build.tcl'),tcl.join('\n'));
await fs.writeFile(path.join(root,'scripts','project_info.json'),JSON.stringify({pdsPath:file},null,2)+'\n');
await fs.writeFile(path.join(root,'scripts','pds_build.json'),JSON.stringify({pdsPath:file,timeoutSec:900,cache:false,backupOldBuildDirs:false,detail:'full'},null,2)+'\n');
console.log(JSON.stringify({ok:true,pdsPath:file,sources:rtl,backup},null,2));
