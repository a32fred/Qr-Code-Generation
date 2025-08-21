use qrcode::QrCode;
use image::{ImageBuffer, Rgba, RgbaImage};
use crate::models::QRRequest;

pub fn generate_qr(req: &QRRequest, plan: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    // Generate QR code
    let code = QrCode::new(&req.data)?;
    let image = code.render::<Rgba<u8>>()
        .min_dimensions(req.size, req.size)
        .max_dimensions(req.size, req.size)
        .build();

    // Apply customizations for premium plans
    let final_image = if plan != "free" {
        apply_customizations(image, req, plan)?
    } else {
        image
    };

    // Convert to PNG bytes
    let mut png_data = Vec::new();
    {
        use image::codecs::png::PngEncoder;
        use image::ImageEncoder;
        
        let encoder = PngEncoder::new(&mut png_data);
        encoder.write_image(
            final_image.as_raw(),
            final_image.width(),
            final_image.height(),
            image::ColorType::Rgba8,
        )?;
    }

    Ok(png_data)
}

fn apply_customizations(
    mut image: RgbaImage,
    req: &QRRequest,
    plan: &str,
) -> Result<RgbaImage, Box<dyn std::error::Error>> {
    // Custom colors for Pro+ plans
    if plan == "pro" || plan == "business" {
        let fg_color = parse_hex_color(&req.color)?;
        let bg_color = parse_hex_color(&req.bg_color)?;
        
        // Replace colors
        for pixel in image.pixels_mut() {
            if pixel[3] > 0 { // If not transparent
                if pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0 {
                    // Replace black with custom foreground
                    *pixel = fg_color;
                } else {
                    // Replace white with custom background
                    *pixel = bg_color;
                }
            }
        }
    }

    // TODO: Logo overlay for Pro+ plans
    if let Some(_logo_base64) = &req.logo {
        if plan == "pro" || plan == "business" {
            // Logo implementation would go here
            // For now, just return the image as-is
        }
    }

    Ok(image)
}

fn parse_hex_color(hex: &str) -> Result<Rgba<u8>, Box<dyn std::error::Error>> {
    let hex = hex.trim_start_matches('#');
    
    if hex.len() != 6 {
        return Ok(Rgba([0, 0, 0, 255])); // Default to black
    }

    let r = u8::from_str_radix(&hex[0..2], 16)?;
    let g = u8::from_str_radix(&hex[2..4], 16)?;
    let b = u8::from_str_radix(&hex[4..6], 16)?;

    Ok(Rgba([r, g, b, 255]))
}