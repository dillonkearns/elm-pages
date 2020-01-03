const fs = require('fs');
module.exports = { ensureDirSync, deleteIfExists };

function ensureDirSync(dirpath) {
    try {
      fs.mkdirSync(dirpath, { recursive: true });
    } catch (err) {
      if (err.code !== "EEXIST") throw err;
    }
  }
  
  function deleteIfExists(/** @type string */ filePath) {
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }
  }