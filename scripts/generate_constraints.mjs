import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const map = JSON.parse(await fs.readFile(path.join(root, 'constraints', 'j8_pins.json'), 'utf8'));
if (map.gpio.length !== 34 || map.gpio.some((row, index) => row.j8 !== index + 3)) {
  throw new Error('J8 GPIO must cover physical pins 3 through 36 exactly once');
}
const pins = [...map.gpio, ...map.fixed].map(row => row.pin);
if (new Set(pins).size !== 38) throw new Error('Duplicate package pin');
const lines = [
  '# MES50HP only; PGL50H-6IFBG484. Do not substitute another board pin map.',
  '# Native PDS 2023.2-SP3 define_attribute syntax verified against installed examples.',
  '# J8 GPIO index i corresponds to physical J8 pin i+3.',
  '# External 10 kohm pull-downs on BOTH loopback ends are required for unattended bidirection.',
  '# NONE=TRUE explicitly disables internal bias; no unverified pull-down is assumed.',
  'create_clock -name {clk_50m} [get_ports {clk_50m}] -period {20.000} -waveform {0.000 10.000}',
  '',
  '# KEY1 is asynchronous; reset_sync provides asynchronous assertion and synchronous release.',
  'set_false_path -from [get_ports {rst_n}]',
  '# UART and loopback returns are asynchronous; cut ONLY arrival at the first synchronizer stage.',
  '# Second stage and all downstream logic remain timed by clk_50m.',
  'set_false_path -from [get_ports {uart_rx}] -to [get_cells {u_rx.rx_meta}]',
  'set_false_path -from [get_ports {j8_gpio[*]}] -to [get_cells {u_ctrl.rx_meta[*]}]',
  '# External receivers are asynchronous. Bound register-to-pad propagation to 100 ns.',
  '# This is much smaller than the 100 us settle interval; no invented synchronous board delay.',
  'set_max_delay {100.000} -to [get_ports {j8_gpio[*]}]',
  'set_max_delay {100.000} -to [get_ports {uart_tx}]',
  '',
];
function addPort(port, pin, direction, note) {
  lines.push(`# ${note}`);
  for (const [key, value] of Object.entries({DIRECTION:direction,LOC:pin,VCCIO:'3.3',STANDARD:'LVCMOS33',NONE:'TRUE'})) {
    lines.push(`define_attribute {p:${port}} {PAP_IO_${key}} {${value}}`);
  }
  if (direction !== 'INPUT') {
    lines.push(`define_attribute {p:${port}} {PAP_IO_DRIVE} {4}`);
    lines.push(`define_attribute {p:${port}} {PAP_IO_SLEW} {SLOW}`);
  }
  lines.push('');
}
for (const row of map.fixed) addPort(row.port, row.pin, row.direction, row.source);
for (const [index, row] of map.gpio.entries()) addPort(`j8_gpio[${index}]`,row.pin,'INOUT',`J8-${row.j8} ${row.network}, table 3-12`);
const output = path.join(root, 'constraints', 'j8_gpio_mes50hp.fdc');
await fs.writeFile(output, lines.join('\n') + '\n');
console.log(JSON.stringify({ok:true,ports:38,output},null,2));
