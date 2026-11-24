const path=require('node:path');
const {execFileSync}=require('node:child_process');
// Existing canonical logo/maskot files are preserved; the extension is repeatable.
for(const script of ['extend-package.cjs','verify-assets.cjs','catalog-and-check.cjs']){
  execFileSync(process.execPath,[path.join(__dirname,script)],{stdio:'inherit'});
}
