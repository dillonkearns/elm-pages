// thanks to Wes Bos for the initial code template https://github.com/wesbos/wesbos/blob/38e7bf5126758d17c10890832fe58542f6d19861/functions/ogimage/ogimage.js
// https://wesbos.com/new-wesbos-website
const chrome = require("chrome-aws-lambda");
const puppeteer = require("puppeteer-core");
// const wait = require('waait');

const cached = new Map();

const exePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

async function getOptions(isDev) {
  if (isDev) {
    return {
      product: "chrome",
      args: [],
      executablePath: exePath,
      headless: true,
    };
  }
  return {
    product: "chrome",
    args: chrome.args,
    executablePath: await chrome.executablePath,
    headless: chrome.headless,
    defaultViewport: chrome.defaultViewport,
  };
}

async function getScreenshot(url, isDev) {
  console.log({ isDev, url: process.env.URL });
  // first check if this value has been cached
  const cachedImage = cached.get(url);
  if (cachedImage) {
    console.log("Found cached image!");
    return cachedImage;
  }
  const options = await getOptions(isDev);
  const browser = await puppeteer.launch(options);
  const page = await browser.newPage();
  //  await page.setViewport({ width: 1600, height: 1600, deviceScaleFactor: 1 });
  await page.setViewport({ width: 1440, height: 1024 });

  // await page.goto(url, { waitUntil: "networkidle0" });
  await page.goto(url);
  await wait(1000);

  const buffer = await page.screenshot({ type: "png" });
  const base64Image = buffer.toString("base64");
  cached.set(url, base64Image);
  return base64Image;
}

// Docs on event and context https://www.netlify.com/docs/functions/#the-handler-method
exports.handler = async (event, context) => {
  const url = decodeURIComponent(event.path.replace(/^.*\/screenshot\//, ''))

  console.log({ url });
  const photoBuffer = await getScreenshot(
    url,
    // Here we need to pass a boolean to say if we are on the server. Netlify has a bug where process.env.NETLIFY is undefined in functions so I'm using one of the only vars I can find
    // !process.env.NETLIFY
    process.env.URL.includes("http://localhost")
  );
  return {
    statusCode: 200,
    body: photoBuffer,
    // headers: {'Cache-Control': 'public, max-age=600, s-maxage=604800 stale-while-revalidate=31540000'},
    // `stale-while-revalidate=31540000` - we never want to make the user wait to see a screenshot. No matter how stale the cached image is,
    // we will go fetch it in the background but we'd prefer for the user to get a stale screenshot than waiting for a long time for images to load for the showcase
    // see https://www.youtube.com/watch?v=bfLFHp7Sbkg
    headers: {'Cache-Control': 'public, max-age=600, s-maxage=60 stale-while-revalidate=31540000'},
    isBase64Encoded: true,
  };
};

function wait(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
