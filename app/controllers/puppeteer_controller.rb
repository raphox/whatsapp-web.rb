require 'puppeteer'
require 'rmagick'
require 'rqrcode'

class PuppeteerController < ApplicationController
  PLATTE = OpenStruct.new({
    WHITE_ALL: "\u2588",
    WHITE_BLACK: "\u2580",
    BLACK_WHITE: "\u2584",
    BLACK_ALL: ' ',
  })

  def index
    result = []

    Puppeteer.launch(headless: false, slow_mo: 50, args: ['--guest', '--window-size=1280,800']) do |browser|
      this = OpenStruct.new

      this.pupBrowser = browser
      this.pupPage = page = browser.new_page

      page.viewport = Puppeteer::Viewport.new(width: 1280, height: 800)
      page.goto('https://web.whatsapp.com/', wait_until: 'load', timeout: 0)

      # Check if retry button is present
      page.query_selector('div[data-ref] > span > button')&.click

      # Wait for QR Code
      page.wait_for_selector('canvas')
      data = page.eval_on_selector('canvas', <<~JAVASCRIPT)
        canvas => {
          return {
            urlCode: canvas.closest('[data-ref]').getAttribute('data-ref'),
            base64: canvas.toDataURL(),
          }
        }
      JAVASCRIPT

      render_qrcode!(data)

      moduleraid_str = File.read('./node_modules/@pedroslopez/moduleraid/moduleraid.js')
      injected_str = File.read('./node_modules/whatsapp-web.js/src/util/Injected.js')

      page.evaluate(
        injected_str[/exports\.ExposeStore = (.+?\n})/m, 1],
        moduleraid_str[/const moduleRaid = (.+?\n})/m, 1]
      )
    end

    render json: { items: result }
  end

  private

  def render_qrcode!(data)
    qrcode = RQRCode::QRCode.new(data['urlCode']).qrcode
    module_count = qrcode.module_count
    module_data = qrcode.modules
    odd_row = module_count.odd?

    module_data.push(Array.new(module_count, false)) if odd_row

    # blob = Base64.decode64(data['data']['data:image/png;base64,'.length .. -1])
    # image = Magick::Image.from_blob(blob).first
    # image.write('./qrcode.png')
    # image.colorspace = Magick::GRAYColorspace
    # image.resize!(module_count, new_size, Magick::BoxFilter, 0)
    # image.write('./qrcode_resize.png')

    output = "#{Array.new(module_count + 2, PLATTE.BLACK_WHITE).join}\n"

    (0...module_count).step(2).each do |row|
      break unless module_data[row + 1]

      output += PLATTE.WHITE_ALL

      (0...module_count).each do |col|
        output += if module_data[row][col] == false && module_data[row + 1][col] == false
                    PLATTE.WHITE_ALL
                  elsif module_data[row][col] == false && module_data[row + 1][col] == true
                    PLATTE.WHITE_BLACK
                  elsif module_data[row][col] == true && module_data[row + 1][col] == false
                    PLATTE.BLACK_WHITE
                  else
                    PLATTE.BLACK_ALL
                  end
      end

      output += "#{PLATTE.WHITE_ALL}\n"
    end

    output += "#{Array.new(module_count + 2, PLATTE.BLACK_WHITE).join}\n" unless odd_row

    puts output
  end
end
