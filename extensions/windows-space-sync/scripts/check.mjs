// SPDX-License-Identifier: MPL-2.0
import {readdir,readFile} from 'node:fs/promises';import {join} from 'node:path';import {spawnSync} from 'node:child_process';
async function files(directory){const result=[];for(const entry of await readdir(directory,{withFileTypes:true})){const path=join(directory,entry.name);if(entry.isDirectory())result.push(...await files(path));else result.push(path);}return result;}
const paths=await files('extension');let count=0;
for(const path of paths.filter(path=>path.endsWith('.js'))) {const result=spawnSync(process.execPath,['--check',path],{encoding:'utf8'});if(result.status!==0){process.stderr.write(result.stderr);process.exit(1);}count++;}
const manifest=JSON.parse(await readFile('extension/manifest.json','utf8'));if(manifest.manifest_version!==3)throw new Error('Manifest V3 required');
for(const path of [manifest.background.service_worker,manifest.action.default_popup,manifest.options_page])await readFile(join('extension',path));
console.log(`${count} JavaScript modules parse; manifest entry points resolve. This is not a browser runtime test.`);
