const { chromium } = require('playwright-core'); const path=require('path');
(async()=>{const b=await chromium.launch({executablePath:'/usr/bin/google-chrome',args:['--no-sandbox']});
const p=await b.newPage({viewport:{width:1800,height:1200},deviceScaleFactor:2});
await p.goto('file://'+path.resolve(__dirname,'../mock.html'));await p.evaluate(()=>document.fonts.ready);
await p.screenshot({path:path.resolve(__dirname,'../shots/00-board.png'),fullPage:true});
await p.addStyleTag({content:'.screen{border-radius:0!important;box-shadow:none!important}'});
for(const el of await p.locator('.screen').all()){const n=await el.getAttribute('data-shot');await el.screenshot({path:path.resolve(__dirname,`../shots/${n}.png`)});}
await b.close();})();
