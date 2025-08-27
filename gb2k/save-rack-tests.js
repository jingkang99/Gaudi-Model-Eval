import puppeteer from 'puppeteer';
import fs from 'fs';

const args = process.argv;
var outdir = args[2];

fs.rmSync(outdir, { recursive: true, force: true });
fs.mkdirSync(outdir);
fs.mkdirSync(outdir + '/png');

const racks = new Map();
racks.set('001', 'http://10.43.251.42/monitor/Oracle/OC01.html');
racks.set('003', 'http://10.43.251.42/monitor/Oracle/OC03.html');
racks.set('004', 'http://10.43.251.42/monitor/Oracle/OC04.html');

racks.set('006', 'http://10.43.251.42/monitor/Oracle/OC06.html');
racks.set('007', 'http://10.43.251.42/monitor/Oracle/OC07.html');
racks.set('008', 'http://10.43.251.42/monitor/Oracle/OC08.html');
racks.set('009', 'http://10.43.251.42/monitor/Oracle/OC09.html');
racks.set('010', 'http://10.43.251.42/monitor/Oracle/OC10.html');
racks.set('011', 'http://10.43.251.42/monitor/Oracle/OC11.html');
racks.set('012', 'http://10.43.251.42/monitor/Oracle/OC12.html');

racks.set('014', 'http://10.43.251.42/monitor/Oracle/OC14.html');
racks.set('015', 'http://10.43.251.42/monitor/Oracle/OC15.html');
racks.set('016', 'http://10.43.251.42/monitor/Oracle/OC16.html');
racks.set('017', 'http://10.43.251.42/monitor/Oracle/OC17.html');

racks.set('020', 'http://10.43.251.42/monitor/Oracle/OCMODEL0.html');

//racks.set('030', 'http://10.43.251.45/monitor/Oracle/NEWOC05.html');
//racks.set('031', 'http://10.43.251.45/monitor/Oracle/NEWOC12.html');

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

	await sleep(5000);

	await page.screenshot({ path: outdir + "/png/" + key + '.png', fullPage: true });

	const htmlContent = await page.content();
	fs.writeFileSync( outdir + '/' +  key + '.html', htmlContent);
}

await browser.close();
