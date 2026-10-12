import fs from 'node:fs/promises';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const file=path.join(root,'pds','pangu50k_j8_gpio_diag.pds');
for (const processName of ['pds.exe','pds_shell.exe']) {
  const status=spawnSync('tasklist.exe',['/FI',`IMAGENAME eq ${processName}`,'/FO','CSV','/NH'],{encoding:'utf8',windowsHide:true});
  if (status.status!==0 || status.stdout.toLowerCase().includes(`"${processName}"`)) throw new Error('PDS must be idle before updating bitstream options');
}
let body=await fs.readFile(file,'utf8');
if (!body.includes('(_option master_configuration_clock_frequency')) {
  const start=body.indexOf('(_command cmd_gen_bitstream');
  if (start<0) throw new Error('No bitstream command found');
  const at=body.indexOf('\n',start)+1;
  body=body.slice(0,at)+'            (_option master_configuration_clock_frequency (_string "40M"))\n'+body.slice(at);
  const backup=path.join(root,'pds','.pango-mcp','project-backups',`bitstream-${new Date().toISOString().replace(/[:.]/g,'-')}`);
  await fs.mkdir(backup,{recursive:true});
  await fs.copyFile(file,path.join(backup,path.basename(file)));
  await fs.writeFile(file,body);
}
console.log(JSON.stringify({ok:true,pdsPath:file,masterConfigurationClock:'40M'}));
