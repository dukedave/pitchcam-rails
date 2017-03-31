require 'opencv'
include OpenCV

class VideoChannel < ApplicationCable::Channel

  def subscribed
    stream_for uuid
    config = Configs.instance.get uuid
    VideoChannel.broadcast_to uuid, action: 'ready', config_updated_at: config.updated_at
  end

  def frame(data)
    uri = URI::Data.new data['image_uri']
    File.open('tmp/image.jpg', 'wb') { |f| f.write(uri.data) }
    image = IplImage.load 'tmp/image.jpg'

    config = Configs.instance.get uuid

    # Track mask
    track_mask = CvMat.new image.size.height, image.size.width, :cv8uc1, 1
    track_mask.set_zero!
    config.track.render_mask_to track_mask
    masked_track_image = image.clone.set CvColor::White, track_mask.not

    tmp_file =  'tmp/output.png'
    masked_track_image.save_image tmp_file
    output_encoded = Base64.strict_encode64 File.open(tmp_file, 'rb').read
    output_uri = "data:image/png;base64,#{output_encoded}"

    image_attrs = { uri: output_uri, createdAt: data['created_at'] }
    debug = { expected_car_pixel_count: (config.track.car_radius_world**2 * Math::PI).round }
    DebugRenderChannel.broadcast_to uuid, color: false, image: image_attrs.to_json, debug: debug.to_json

    image_processor = config.image_processor
    dirty_colors = image_processor.handle_image masked_track_image
    DebugRenderChannel.broadcast_to uuid, update: dirty_colors if dirty_colors.present?

    config.colors.each do |color|
      color_mask = color.hsv_map masked_track_image
      masked_color_image = image.clone.set CvColor::White, color_mask.not
      config.track.render_outline_to masked_color_image, CvColor::Black

      tmp_file =  'tmp/output.png'
      masked_color_image.save_image tmp_file
      output_encoded = Base64.strict_encode64 File.open(tmp_file, 'rb').read
      output_uri = "data:image/png;base64,#{output_encoded}"

      image_attrs = { uri: output_uri, createdAt: data['created_at'] }

      latest_world_position = image_processor.colors_positions[color].to_point
      latest_track_position = latest_world_position && config.track.position_from_world(latest_world_position)
      positions = { world: latest_world_position, track: latest_track_position }
      debug = image_processor.colors_debug[color]
      DebugRenderChannel.broadcast_to uuid, color: true, name: color.name, image: image_attrs.to_json, positions: positions.to_json, debug: debug.to_json
    end

    VideoChannel.broadcast_to uuid, action: 'snap'
  end
end
