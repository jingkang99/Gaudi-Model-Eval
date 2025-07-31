import puppeteer from 'puppeteer';
import fs from 'fs';

const args = process.argv;
var outdir = args[2];

fs.rmSync(outdir, { recursive: true, force: true });
fs.mkdirSync(outdir);
fs.mkdirSync(outdir + '/png');

const racks = new Map();
racks.set('001', 'http://10.43.251.42/firmware/system-list?gid=25');
racks.set('003', 'http://10.43.251.42/firmware/system-list?gid=24');
racks.set('004', 'http://10.43.251.42/firmware/system-list?gid=27');
racks.set('006', 'http://10.43.251.42/firmware/system-list?gid=28');
racks.set('007', 'http://10.43.251.42/firmware/system-list?gid=29');
racks.set('008', 'http://10.43.251.42/firmware/system-list?gid=30');
racks.set('009', 'http://10.43.251.42/firmware/system-list?gid=31');
racks.set('010', 'http://10.43.251.42/firmware/system-list?gid=32');
racks.set('011', 'http://10.43.251.42/firmware/system-list?gid=33');
racks.set('014', 'http://10.43.251.42/firmware/system-list?gid=36');
racks.set('015', 'http://10.43.251.42/firmware/system-list?gid=37');
racks.set('016', 'http://10.43.251.42/firmware/system-list?gid=38');
racks.set('017', 'http://10.43.251.42/firmware/system-list?gid=39');
racks.set('005', 'http://10.43.251.45/firmware/system-list?gid=23');
racks.set('012', 'http://10.43.251.45/firmware/system-list?gid=24');

const browser = await puppeteer.launch({
	args: ['--no-sandbox', '--disable-setuid-sandbox'],
});
const page = await browser.newPage();

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

for (const [key, value] of racks.entries()) {
	console.log(`rack : ${key}, url: ${value}`);

	await page.goto( value );
	await page.setViewport({width: 1080, height: 1024});

	await sleep(2000);

	await page.screenshot({ path: outdir + "/png/" + key + '.png', fullPage: true });

	const htmlContent = await page.content();
	fs.writeFileSync( outdir + '/' +  key + '.html', htmlContent);
}

await browser.close();
