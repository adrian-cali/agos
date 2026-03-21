/**
 * GOOGLE APPS SCRIPT FOR AGOS GRAYWATER DATA LOGGER
 * 
 * Instructions:
 * 1. Create a new Google Spreadsheet.
 * 2. Create three tabs/sheets named exactly:
 *    - sensor_readings
 *    - sensor_rollups_hourly 
 *    - sensor_rollups_daily
 * 3. Add headers to row 1:
 *    - sensor_readings: | timestamp | turbidity | ph | tds |
 *    - both rollup sheets: | timestamp | count | ph_avg | ph_max | ph_min | tds_avg | tds_max | tds_min | turbidity_avg | turbidity_max | turbidity_min |
 * 4. Go to Extensions > Apps Script. Replace code with this script.
 * 5. Click Deploy > New Deployment.
 * 6. Type: Web App | Execute as: Me | Who has access: Anyone
 * 7. Copy the Web App URL and paste it into the ESP32 code's GOOGLE_SCRIPT_URL.
 * 8. Set up Time-Driven Triggers in Google Apps Script!
 */

// Handle incoming HTTP GET requests from the ESP32
function doGet(e) {
  try {
    var turbidity = e.parameter.turbidity;
    var ph = e.parameter.ph;
    var tds = e.parameter.tds;
    
    if (turbidity == undefined || ph == undefined || tds == undefined) {
      return ContentService.createTextOutput("Error: Missing data fields.");
    }
    
    var timestamp = new Date();
    var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = spreadsheet.getSheetByName("sensor_readings");
    
    if (!sheet) {
      return ContentService.createTextOutput("Error: Sheet 'sensor_readings' not found.");
    }
    
    sheet.appendRow([timestamp, turbidity, ph, tds]);
    return ContentService.createTextOutput("Success: Data saved.");
    
  } catch (err) {
    return ContentService.createTextOutput("Error: " + err.toString());
  }
}

// Helper to accumulate stats
function getStats(data, startTime, endTime) {
  var count = 0;
  var sumPh = 0, maxPh = -Infinity, minPh = Infinity;
  var sumTds = 0, maxTds = -Infinity, minTds = Infinity;
  var sumTurbidity = 0, maxTurbidity = -Infinity, minTurbidity = Infinity;

  for (var i = 1; i < data.length; i++) {
    var rowDate = new Date(data[i][0]);
    if (rowDate >= startTime && rowDate <= endTime) {
      var turb = parseFloat(data[i][1] || 0);
      var ph = parseFloat(data[i][2] || 0);
      var tds = parseFloat(data[i][3] || 0);
      
      sumPh += ph; sumTds += tds; sumTurbidity += turb;
      
      if (ph > maxPh) maxPh = ph; if (ph < minPh) minPh = ph;
      if (tds > maxTds) maxTds = tds; if (tds < minTds) minTds = tds;
      if (turb > maxTurbidity) maxTurbidity = turb; if (turb < minTurbidity) minTurbidity = turb;
      
      count++;
    }
  }

  if (count === 0) return null;

  return [
    count,
    (sumPh / count).toFixed(2), maxPh, minPh,
    (sumTds / count).toFixed(2), maxTds, minTds,
    (sumTurbidity / count).toFixed(2), maxTurbidity, minTurbidity
  ];
}

// ----------------------------------------------------
// HOURLY ROLLUPS TRIGGER FUNCTION
// ----------------------------------------------------
function rollupHourlyData() {
  var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  var rawSheet = spreadsheet.getSheetByName("sensor_readings");
  var hourlySheet = spreadsheet.getSheetByName("sensor_rollups_hourly");
  
  if (!rawSheet || !hourlySheet) return;
  
  var now = new Date();
  var oneHourAgo = new Date(now.getTime() - (60 * 60 * 1000));
  
  var data = rawSheet.getDataRange().getValues();
  var stats = getStats(data, oneHourAgo, now);
  
  if (stats) {
    var blockTime = new Date();
    blockTime.setMinutes(0, 0, 0); 
    
    var row = [blockTime].concat(stats);
    hourlySheet.appendRow(row);
  }
}

// ----------------------------------------------------
// DAILY ROLLUPS TRIGGER FUNCTION
// ----------------------------------------------------
function rollupDailyData() {
  var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  // Usually daily reads from hourly, but it's much more accurate to run max/min off the RAW readings 
  // so we'll pull from sensor_readings for the daily pass as well.
  var rawSheet = spreadsheet.getSheetByName("sensor_readings");
  var dailySheet = spreadsheet.getSheetByName("sensor_rollups_daily");
  
  if (!rawSheet || !dailySheet) return;
  
  var now = new Date();
  var oneDayAgo = new Date(now.getTime() - (24 * 60 * 60 * 1000));
  
  var data = rawSheet.getDataRange().getValues();
  var stats = getStats(data, oneDayAgo, now);
  
  if (stats) {
    var blockTime = new Date();
    blockTime.setHours(0, 0, 0, 0); 
    
    var row = [blockTime].concat(stats);
    dailySheet.appendRow(row);
  }
}
