import fs from 'fs';
import path from 'path';

const migrationsDir = 'd:/New folder/tvstreamz/tvstreamz/supabase/migrations';
const csvPath = 'c:/Users/flame143/Downloads/channels-export-2026-05-19_09-37-11.csv';
const outputPath = 'd:/New folder/tvstreamz/tvstreamz/setup_everything.sql';

// 1. Parse CSV function
function parseCSV(text) {
  const result = [];
  let row = [];
  let cell = '';
  let inQuotes = false;
  
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    const nextChar = text[i + 1];
    
    if (inQuotes) {
      if (char === '"') {
        if (nextChar === '"') {
          cell += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell += char;
      }
    } else {
      if (char === '"') {
        inQuotes = true;
      } else if (char === ';') {
        row.push(cell);
        cell = '';
      } else if (char === '\r' || char === '\n') {
        if (char === '\r' && nextChar === '\n') {
          i++;
        }
        row.push(cell);
        result.push(row);
        row = [];
        cell = '';
      } else {
        cell += char;
      }
    }
  }
  if (cell !== '' || row.length > 0) {
    row.push(cell);
    result.push(row);
  }
  return result;
}

function sqlEscape(val) {
  if (val === undefined || val === null || val === '') {
    return 'NULL';
  }
  // If it's a boolean string
  if (val.toLowerCase() === 'true') return 'true';
  if (val.toLowerCase() === 'false') return 'false';
  
  // If it looks like a number and isn't a string identifier
  if (!isNaN(val) && val.trim() !== '' && !val.includes('-') && !val.includes(':')) {
    return val;
  }
  
  // Otherwise, treat as string and escape single quotes
  const escaped = val.replace(/'/g, "''");
  return `'${escaped}'`;
}

async function run() {
  try {
    console.log('Starting migration compilation...');
    
    // Read all migrations
    const files = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort();
      
    let sqlContent = '';
    
    for (const file of files) {
      const filePath = path.join(migrationsDir, file);
      console.log(`Adding migration: ${file}`);
      const content = fs.readFileSync(filePath, 'utf-8');
      sqlContent += `-- --- MIGRATION: ${file} ---\n`;
      sqlContent += content;
      sqlContent += '\n\n';
    }
    
    // Read and parse CSV
    console.log(`Reading CSV: ${csvPath}`);
    const csvContent = fs.readFileSync(csvPath, 'utf-8');
    const parsed = parseCSV(csvContent);
    
    if (parsed.length === 0) {
      throw new Error('CSV is empty');
    }
    
    // Get headers
    const rawHeaders = parsed[0];
    // Map 'cid' or 'id' to 'id'
    const headers = rawHeaders.map(h => h.trim() === 'cid' ? 'id' : h.trim());
    
    console.log(`Found headers: ${headers.join(', ')}`);
    console.log(`Parsing ${parsed.length - 1} channels...`);
    
    sqlContent += `-- -----------------------------------------------------\n`;
    sqlContent += `-- --- INSERT CHANNELS DATA FROM CSV ---\n`;
    sqlContent += `-- -----------------------------------------------------\n\n`;
    
    // Disable triggers temporarily to avoid updated_at override if needed, 
    // but standard insert should be fine since we provide updated_at.
    sqlContent += `ALTER TABLE public.channels DISABLE TRIGGER ALL;\n\n`;
    
    for (let i = 1; i < parsed.length; i++) {
      const row = parsed[i];
      if (row.length < 2 || !row[0]) continue; // Skip empty rows
      
      const columns = [];
      const values = [];
      
      for (let j = 0; j < headers.length; j++) {
        const header = headers[j];
        let val = row[j];
        
        // Ensure we don't map columns outside the row bounds
        if (val === undefined) val = '';
        
        columns.push(header);
        values.push(sqlEscape(val));
      }
      
      sqlContent += `INSERT INTO public.channels (${columns.join(', ')})\nVALUES (${values.join(', ')})\nON CONFLICT (id) DO UPDATE SET\n`;
      
      const updates = [];
      for (let j = 0; j < headers.length; j++) {
        if (headers[j] === 'id') continue; // Don't update ID
        updates.push(`${headers[j]} = EXCLUDED.${headers[j]}`);
      }
      sqlContent += `  ${updates.join(',\n  ')};\n\n`;
    }
    
    sqlContent += `ALTER TABLE public.channels ENABLE TRIGGER ALL;\n`;
    
    fs.writeFileSync(outputPath, sqlContent, 'utf-8');
    console.log(`Successfully generated Setup SQL file at: ${outputPath}`);
    
  } catch (error) {
    console.error('Error occurred:', error);
  }
}

run();
