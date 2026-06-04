use chrono::Local;
use std::collections::HashMap;
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::path::Path;
use std::time::Duration;

// ANSI Color Constants
const RED: &str = "\x1b[0;31m";
const YLW: &str = "\x1b[0;33m";
const BLU: &str = "\x1b[0;34m";
const BLB: &str = "\x1b[1;34m";
const BCY: &str = "\x1b[1;36m";
const NCL: &str = "\x1b[0m";

fn get_ora_pn_map() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    m.insert("8209200", "672042983179 CBL-CDAT-8209200-OC018");
    m.insert("8232688", "672042982677 CBL-CDAT-8232688-OC018");
    m.insert("8232689", "672042982684 CBL-CDAT-8232689-OC018");
    m.insert("8232690", "672042982691 CBL-CDAT-8232690-OC018");
    m.insert("8232719", "672042981762 CBL-CDAT-8232719-OC018");
    m.insert("8232720", "672042982530 CBL-CDAT-8232720-OC018");
    m.insert("8232942", "672042982585 CBL-CDAT-8232942-OC018");
    m.insert("8236716", "672042983193 CBL-CUSB-1081Q-90J-OC018");
    m.insert("8232678", "672042982554 CBL-MCIO-1218M5-OC018");
    m.insert("8234289", "672042980529 CBL-MCIO-1220M5R-OC018");
    m.insert("8234290", "672042982745 CBL-MCIO-1230M5-OC018");
    m.insert("8234291", "672042982592 CBL-MCIO-1230M5R-OC018");
    m.insert("8234292", "672042982561 CBL-MCIO-1233M5R-OC018");
    m.insert("8234295", "672042982608 CBL-MCIO-1260M5-OC018");
    m.insert("8236715", "672042984282 CBL-MCIO-1445AM5B1-OC018");
    m.insert("8234293", "672042934836 CBL-MCIO-1445AM5RF");
    m.insert("8234296", "672042982721 CBL-PWEX-0946Y-17-OC018");
    m.insert("8234297", "672042982714 CBL-PWEX-1093-36-OC018");
    m.insert("8234304", "672042982738 CBL-PWEX-1093-A0-OC018");
    m.insert("8234300", "672042983186 CBL-PWEX-1316-60-OC018");
    m.insert("8232679", "672042982615 CBL-PWEX-8232679-OC018");
    m.insert("8232703", "672042982707 CBL-PWEX-8232703-OC018");
    m.insert("8232707", "672042982752 CBL-PWEX-8232707-OC018");
    m.insert("8232708", "672042982622 CBL-PWEX-8232708-OC018");
    m.insert("8232709", "672042982639 CBL-PWEX-8232709-OC018");
    m.insert("8232710", "672042982646 CBL-PWEX-8232710-OC018");
    m.insert("8232711", "672042982653 CBL-PWEX-8232711-OC018");
    m.insert("8232713", "672042982660 CBL-PWEX-8232713-OC018");
    m
}

fn send_to_printer(printer_ip: &str, payload: &str) -> std::io::Result<()> {
    let address = format!("{}:9100", printer_ip);
    let mut stream = TcpStream::connect_timeout(
        &address.parse().unwrap(),
        Duration::from_secs(3),
    )?;
    stream.write_all(payload.as_bytes())?;
    Ok(())
}

fn separator(printer_ip: &str, partnm: &str, upcstr: &str, oracle: &str) {
    let zpl = format!(
        "^XA\n^PW380\n^LL200\n^CF0,19\n^FO25,25^A0N,50,25^FD{}^FS^FO25,95^A0N,50,25^FD{}^FS^FO25,155^A0N,50,25^FD{}^FS^XZ",
        partnm, upcstr, oracle
    );
    if let Err(e) = send_to_printer(printer_ip, &zpl) {
        eprintln!("{}Printer Error: {}{}", RED, e, NCL);
    }
}

fn print_label(printer_ip: &str, ora_map: &HashMap<&str, &str>, oracle: &str, counts: usize) {
    let entry = match ora_map.get(oracle) {
        Some(e) => e,
        None => return,
    };

    let parts: Vec<&str> = entry.split_whitespace().collect();
    if parts.len() < 2 {
        return;
    }
    let upcstr = parts[0];
    let partnm = parts[1];

    let now = Local::now();
    let redate = now.format("%m/%y").to_string();

    // Mappings for the custom sequence generation rules
    let mons: HashMap<&str, &str> = [("01","1"), ("02","2"), ("03","3"), ("04","4"), ("05","5"), ("06","6"), ("07","7"), ("08","8"), ("09","9"), ("10","A"), ("11","B"), ("12","C")].iter().cloned().collect();
    let days: HashMap<&str, &str> = [("01","1"), ("02","2"), ("03","3"), ("04","4"), ("05","5"), ("06","6"), ("07","7"), ("08","8"), ("09","9"), ("10","A"), ("11","B"), ("12","C"), ("13","D"), ("14","E"), ("15","F"), ("16","G"), ("17","H"), ("18","I"), ("19","J"), ("20","K"), ("21","L"), ("22","M"), ("23","N"), ("24","O"), ("25","P"), ("26","Q"), ("27","R"), ("28","S"), ("29","T"), ("30","U"), ("31","V")].iter().cloned().collect();
    let hours: HashMap<&str, &str> = [("01","1"), ("02","2"), ("03","3"), ("04","4"), ("05","5"), ("06","6"), ("07","7"), ("08","8"), ("09","9"), ("10","A"), ("11","B"), ("12","C"), ("13","D"), ("14","E"), ("15","F"), ("16","G"), ("17","H"), ("18","I"), ("19","J"), ("20","K"), ("21","L"), ("22","M"), ("23","N"), ("24","O")].iter().cloned().collect();
    let years: HashMap<&str, &str> = [("26","X"), ("27","Y"), ("28","Z"), ("29","R"), ("30","S"), ("31","T")].iter().cloned().collect();

    let today_mon = now.format("%m").to_string();
    let today_day = now.format("%d").to_string();
    let today_hou = now.format("%H").to_string();
    let today_yea = now.format("%y").to_string();

    let upc_last_5 = if upcstr.len() >= 5 {
        &upcstr[upcstr.len() - 5..]
    } else {
        upcstr
    };

    let y_char = years.get(today_yea.as_str()).unwrap_or(&"");
    let m_char = mons.get(today_mon.as_str()).unwrap_or(&"");
    let d_char = days.get(today_day.as_str()).unwrap_or(&"");
    let h_char = hours.get(today_hou.as_str()).unwrap_or(&"");

    let pre = format!("{}{}{}{}{}", upc_last_5, y_char, m_char, d_char, h_char);

    println!(
        "  print for: {}{}{} {} {} {} {} {}",
        BLU, oracle, NCL, upcstr, partnm, counts, redate, pre
    );
    println!();

    for i in (1..=counts).rev() {
        let seq = format!("{}{:03}", pre, i);
        println!("  {}{}{}", BCY, seq, NCL);

        let zpl = format!(
            "^XA\n^PW380\n^LL200\n^CF0,19\n^BY1,2.5,24\n^FO28,48^BCN,24,N,N,N^FD{upc}^FS\n^FO25,82^FDUPC: {upc}^FS\n^FO25,106^FDSUPER MICRO COO:CHN^FS\n^FO25,130^FD{part}^FS\n^FO25,154^FDREV 1.0 {date}^FS\n^FO25,178^FDSN: {seq}^FS\n^BY1,2.5,24\n^FO28,198^BCN,24,N,N,N^FD{seq}^FS\n^FO25,232^FDOracle PN: {ora}^FS^XZ",
            upc=upcstr, part=partnm, date=redate, seq=seq, ora=oracle
        );

        if let Err(e) = send_to_printer(printer_ip, &zpl) {
            eprintln!("{}Printer Error: {}{}", RED, e, NCL);
        }
    }

    separator(printer_ip, partnm, upcstr, oracle);
    println!();
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let ora_map = get_ora_pn_map();
    let mut printer_ip = String::from("172.30.191.54");

    if args.len() > 1 && args[1] == "-l" {
        println!("  {}Oracle     SMC Cable PN               UPC{}", YLW, NCL);
        for (opn, entry) in &ora_map {
            let orr: Vec<&str> = entry.split_whitespace().collect();
            let upc = orr.get(0).unwrap_or(&"");
            let smc = orr.get(1).unwrap_or(&"");
            println!("  {:<10} {:<25}  {}", opn, smc, upc);
        }
        return;
    }

    if args.len() > 1 && args[1] == "-h" || args.len() < 3 {
        println!("  {}print_labels{} COUNT PN1 PN2 PN3", YLW, NCL);
        return;
    }

    let count: usize = match args[1].parse() {
        Ok(c) => c,
        Err(_) => {
            eprintln!("{}Invalid count provided{}", RED, NCL);
            return;
        }
    };

    if count > 999 {
        println!("{}limited to print up to 999 labels{}", RED, NCL);
        return;
    }

    // Process local INI file configuration if present
    if Path::new("printbatc.ini").exists() {
        if let Ok(file) = File::open("printbatc.ini") {
            let reader = BufReader::new(file);
            for line in reader.lines().map_while(Result::ok) {
                if line.contains("PRINTER") {
                    let parts: Vec<&str> = line.split('=').collect();
                    if parts.len() == 2 {
                        printer_ip = parts[1].trim().to_string();
                        println!("  use printer: {}{}{}", BLB, printer_ip, NCL);
                        break;
                    }
                }
            }
        }
    }

    let arg_pns = &args[2..];
    for pn in arg_pns {
        let entry = ora_map.get(pn.as_str());
        if pn.len() != 7 || entry.is_none() {
            println!("  {}wrong {}{}", YLW, pn, NCL);
            continue;
        }

        print_label(&printer_ip, &ora_map, pn, count);
    }
}
