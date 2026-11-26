const { chromium } = require('playwright-core'); const path=require('path');
(async()=>{const b=await chromium.launch({executablePath:'/usr/bin/google-chrome',args:['--no-sandbox']});
const p=await b.newPage({viewport:{width:1300,height:560},deviceScaleFactor:2});
await p.goto('file://'+path.resolve(__dirname,'../icon/preview.html'));await p.waitForTimeout(300);
await p.screenshot({path:path.resolve(__dirname,'../shots/icon-draft.png'),fullPage:true});
for(const n of ['icon-a-ember','icon-b-iron']){const q=await b.newPage({viewport:{width:1024,height:1024}});await q.goto('file://'+path.resolve(__dirname,`../icon/${n}.svg`));await q.screenshot({path:path.resolve(__dirname,`../icon/${n}-1024.png`)});}
await b.close();})();
