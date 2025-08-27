import fs from 'fs';
import puppeteer from 'puppeteer';
import * as cheerio from 'cheerio';

const args = process.argv;
var outdir = args[2];

if (! fs.existsSync(outdir)) {
	fs.mkdirSync(outdir);
	fs.mkdirSync(outdir + '/png');
}

const sid = 's' + args[3];
const url = "http://10.43.251." + args[3];

var browser = await puppeteer.launch({
	args: ['--no-sandbox', '--disable-setuid-sandbox'],
});
var page = await browser.newPage();
await page.setViewport({width: 1080, height: 1024});

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

const url_logn1=url + "/login?action=login"
const url_rack1=url + '/monitor/Oracle/?model=Oracle'

await page.goto( url_logn1, { waitUntil: 'domcontentloaded' });
await page.type('#UserName', 'test');
await page.type('#PassWord', 'supermicro');
await page.click('#Submit');
await page.waitForNavigation();
await page.goto( url_rack1, { waitUntil: 'domcontentloaded' });
await page.screenshot({ path: outdir + "/png/" + sid +'.png', fullPage: true });

var htmlContent = await page.content();
fs.writeFileSync( outdir + '/' +  sid + '.html', htmlContent);
console.log("  save " + url)

const $ = cheerio.load(htmlContent);
const links = [];
$('a[href]').each((index, element) => {
  const href = $(element).attr('href');
  if (href && href.trim() && href.match(/monitor.*html/) ) {
	links.push(url + href);
  }
});
await page.close();
await browser.close();

// -----------------------

const browser1 = await puppeteer.launch({
	args: ['--no-sandbox', '--disable-setuid-sandbox'],
});
const page1 = await browser1.newPage();
await page1.setViewport({width: 1080, height: 1024});

for (const link of links) {
	await page1.goto( link );
	await sleep(2000);
	const html = await page1.content();

	var rack = link.match(/(SR.+html)/);
	fs.writeFileSync( outdir + '/' +  rack[1], html);
	console.log("  save " + link);
}

await page1.close();
await browser1.close();
