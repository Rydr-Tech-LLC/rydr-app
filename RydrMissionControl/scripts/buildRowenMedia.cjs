// Code-native campaign artwork; no personal photos or invented app screenshots.
const fs=require('node:fs'),path=require('node:path'),sharp=require('sharp'),ts=require('typescript');
const Module=require('node:module');
const manifest=new Module('rowenMedia');
manifest._compile(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../lib/rowenMedia.ts'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,'rowenMedia');
const escape=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;');
(async()=>{
 const out=path.join(__dirname,'../public/rowen-media');fs.mkdirSync(out,{recursive:true});
 for(const [i,asset] of manifest.exports.ROWEN_MEDIA.entries()){
  const dark=i%2===1,bg=dark?'#25121b':'#fff9f3',ink=dark?'#fff9f3':'#25121b',red='#e52c43',muted=dark?'#d9bbc7':'#775960';
  const svg=`<svg width="1080" height="1350" viewBox="0 0 1080 1350" xmlns="http://www.w3.org/2000/svg">
   <rect width="1080" height="1350" fill="${bg}"/>
   <circle cx="1000" cy="970" r="420" fill="${dark?'#522238':'#fbe6e3'}"/>
   <path d="M-80 1120 C240 1120 130 745 480 745 S700 1050 1120 800" fill="none" stroke="${dark?'#693149':'#f4c9c5'}" stroke-width="145"/>
   <path d="M-80 1120 C240 1120 130 745 480 745 S700 1050 1120 800" fill="none" stroke="${bg}" stroke-width="3" stroke-dasharray="20 22"/>
   <rect x="72" y="68" width="74" height="74" rx="24" fill="${red}"/><text x="109" y="121" text-anchor="middle" font-family="Arial,sans-serif" font-size="52" font-weight="700" fill="white">R</text>
   <text x="164" y="122" font-family="Arial,sans-serif" font-size="58" font-weight="700" fill="${ink}">Rydr</text>
   <text x="74" y="258" font-family="Arial,sans-serif" font-size="21" font-weight="700" letter-spacing="3" fill="${red}">${escape(asset.kicker)}</text>
   ${asset.lines.map((line,j)=>`<text x="68" y="${386+j*94}" font-family="Arial,sans-serif" font-size="${line.length>18?70:83}" font-weight="700" letter-spacing="-3" fill="${ink}">${escape(line)}</text>`).join('')}
   <text x="74" y="560" font-family="Arial,sans-serif" font-size="28" fill="${muted}">${escape(asset.detail)}</text>
   <circle cx="480" cy="745" r="65" fill="${red}"/><circle cx="480" cy="745" r="22" fill="${bg}"/>
   <circle cx="870" cy="928" r="25" fill="${red}"/><circle cx="170" cy="975" r="19" fill="${red}"/>
   <rect x="72" y="1185" width="936" height="2" fill="${muted}" opacity="0.3"/>
   <text x="74" y="1252" font-family="Arial,sans-serif" font-size="27" font-weight="700" fill="${ink}">@rydr_tech</text>
   <text x="1006" y="1252" text-anchor="end" font-family="Arial,sans-serif" font-size="26" fill="${muted}">rydr-go.com</text>
  </svg>`;
  await sharp(Buffer.from(svg)).jpeg({quality:92}).toFile(path.join(out,asset.id+'.jpg'));
 }
 console.log('Rendered six 1080 × 1350 JPEG campaign graphics.');
})();
