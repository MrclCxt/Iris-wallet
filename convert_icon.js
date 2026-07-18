const sharp = require('sharp');
const path = require('path');
const fs = require('fs');

const inputSvg = path.resolve(__dirname, 'ICON_IRIS.svg');
const outputDir = path.resolve(__dirname, 'assets/icons');

if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

const sizes = [
  { name: 'icon_1024.png', size: 1024 },
];

async function convert() {
  for (const { name, size } of sizes) {
    const outPath = path.join(outputDir, name);
    await sharp(inputSvg, { density: 300 })
      .resize(size, size)
      .png()
      .toFile(outPath);
    console.log(`Generated: ${outPath}`);
  }
}

convert().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
