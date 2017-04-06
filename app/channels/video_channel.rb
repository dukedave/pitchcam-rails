require 'opencv'
include OpenCV

class VideoChannel < ApplicationCable::Channel

  def subscribed
    stream_for uuid
    config = Configs.instance.get uuid
    VideoChannel.broadcast_to uuid, action: 'ready', config_updated_at: config.updated_at
  end

  def frame(data)
    image = IplImage.load_from_data_uri data['image_uri']
    config = Configs.instance.get uuid

    # Track mask
    masked_track_image = config.track_mask.mask_image image

    if config.null_image
      masked_track_image = masked_track_image.sub config.null_image, config.track_mask.mask(image).not
    end

    masked_track_image_uri = masked_track_image.to_data_uri
    masked_track_image_attrs = { uri: masked_track_image_uri, createdAt: data['created_at'] }
    car_finder = config.car_finder
    debug = { car_radius_world: config.track.car_radius_world, expected_car_pixel_count: car_finder.expected_pixel_count }
    DebugRenderChannel.broadcast_to uuid, color: false, image: masked_track_image_attrs.to_json, debug: debug.to_json

    dirty_colors = car_finder.handle_image masked_track_image
    DebugRenderChannel.broadcast_to uuid, update: dirty_colors if dirty_colors.present?

    config.colors.each do |color|
      color_mask = color.hsv_map masked_track_image
      masked_color_image = image.clone.set CvColor::White, color_mask.not
      config.track.render_outline_to masked_color_image, CvColor::Black

      positions = { world: car_finder.colors_positions[color].to_point }
      if positions[:world]
        positions[:track] = config.track.position_from_world positions[:world]
        render_color_crosshair_to masked_color_image, positions[:world]
      else
        positions[:track] = nil
      end

      masked_color_image_uri = masked_color_image.to_data_uri
      masked_color_image_attrs = { uri: masked_color_image_uri, createdAt: data['created_at'] }

      debug = car_finder.colors_debug[color]

      DebugRenderChannel.broadcast_to uuid, color: true, name: color.name, image: masked_color_image_attrs.to_json, positions: positions.to_json, debug: debug.to_json
    end

    VideoChannel.broadcast_to uuid, action: 'snap'
  end

  def render_color_crosshair_to(image, position)
    horiz_from = CvPoint.new 0, position.y
    horiz_to = CvPoint.new image.width, position.y
    image.line! horiz_from, horiz_to, thickness: 1, color: CvColor::Green

    vert_from = CvPoint.new position.x, 0
    vert_to = CvPoint.new position.x, image.height
    image.line! vert_from, vert_to, thickness: 1, color: CvColor::Green
  end
end
