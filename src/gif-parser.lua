--- Module implementing the gif-parser.

local parse_header = function (gif_data_stream, pos)
   return {
      signature = gif_data_stream:sub(pos, pos + 2),
      version = gif_data_stream:sub(pos + 3, pos + 5)
   }, pos + 6
end

local parse_logical_screen_descriptor = function (gif_data_stream, pos)
   local packed_fields = string.byte(gif_data_stream:sub(pos + 4, pos + 4))
   return {
      logical_screen_width = string.unpack("<I2", gif_data_stream, pos),
      logical_screen_height = string.unpack("<I2", gif_data_stream, pos + 2),
      global_color_table_flag = (packed_fields & 0x80) >> 7,
      color_resolution = (packed_fields & 0x70) >> 4,
      sort_flag = (packed_fields & 0x08) >> 3,
      size_of_global_color_table = packed_fields & 0x07,
      background_color_index = string.byte(gif_data_stream:sub(pos + 5, pos + 5)),
      pixel_aspect_ratio = string.byte(gif_data_stream:sub(pos + 6, pos + 6))
   }, pos + 7
end

local parse_color_table = function (gif_data_stream, pos, size)
   local color_table = {}
   local end_pos = pos + 3 * size
   while pos < end_pos do
      local r, g, b
      r, g, b, pos = string.unpack("BBB", gif_data_stream, pos)
      color_table[#color_table + 1] = { r = r, g = g, b = b }
   end
   return color_table, end_pos
end

local parse_logical_screen = function (gif_data_stream, pos)
   local logical_screen_descriptor, global_color_table
   logical_screen_descriptor, pos = parse_logical_screen_descriptor(gif_data_stream, pos)
   if logical_screen_descriptor.global_color_table_flag == 1 then
      local size = 1 << (logical_screen_descriptor.size_of_global_color_table + 1)
      global_color_table, pos = parse_color_table(gif_data_stream, pos, size)
   end
   return {
      logical_screen_descriptor = logical_screen_descriptor,
      global_color_table = global_color_table
   }, pos
end

local parse_image_descriptor = function (gif_data_stream, pos)
   local packed_fields = string.byte(gif_data_stream:sub(pos + 9, pos + 9))
   return {
      image_separator = gif_data_stream:sub(pos, pos),
      image_left_position = string.unpack("<I2", gif_data_stream, pos + 1),
      image_top_position = string.unpack("<I2", gif_data_stream, pos + 3),
      image_width = string.unpack("<I2", gif_data_stream, pos + 5),
      image_height = string.unpack("<I2", gif_data_stream, pos + 7),
      local_color_table_flag = (packed_fields & 0x80) >> 7,
      interlace_flag = (packed_fields & 0x40) >> 6,
      sort_flag = (packed_fields & 0x20) >> 5,
      reserved = (packed_fields & 0x18) >> 3,
      size_of_local_color_table = packed_fields & 0x07
   }, pos + 10
end

local parse_datasubblocks = function (gif_data_stream, pos)
   local data_subblocks = {}
   while gif_data_stream:sub(pos, pos) ~= "\x00" do
      local block_size = string.byte(gif_data_stream:sub(pos, pos))
      data_subblocks[#data_subblocks + 1] = gif_data_stream:sub(pos + 1, pos + block_size)
      pos = pos + block_size + 1
   end
   return data_subblocks, pos + 1
end

local parse_table_based_image_data = function (gif_data_stream, pos)
   local LZW_minimum_code_size = string.byte(gif_data_stream:sub(pos, pos))
   local image_data
   image_data, pos = parse_datasubblocks(gif_data_stream, pos + 1)
   return {
      LZW_minimum_code_size = LZW_minimum_code_size,
      image_data = image_data
   }, pos
end

local parse_table_based_image = function (gif_data_stream, pos)
   local image_descriptor, local_color_table, table_based_image_data
   image_descriptor, pos = parse_image_descriptor(gif_data_stream, pos)
   if image_descriptor.local_color_table_flag == 1 then
      local size = 1 << (image_descriptor.size_of_local_color_table + 1)
      local_color_table, pos = parse_color_table(gif_data_stream, pos, size)
   end
   table_based_image_data, pos = parse_table_based_image_data(gif_data_stream, pos)
   return {
      image_descriptor = image_descriptor,
      local_color_table = local_color_table,
      image_data = table_based_image_data
   }, pos
end

local parse_graphic_control_extension = function (gif_data_stream, pos)
   local extension_introducer = gif_data_stream:sub(pos, pos)
   local graphic_control_label = gif_data_stream:sub(pos + 1, pos + 1)
   local block_size = string.byte(gif_data_stream:sub(pos + 2, pos + 2))
   local packed_fields = string.byte(gif_data_stream:sub(pos + 3, pos + 3))
   local delay_time = string.unpack("<I2", gif_data_stream, pos + 4)
   local transparent_color_index = string.byte(gif_data_stream:sub(pos + 6, pos + 6))
   return {
      extension_introducer = extension_introducer,
      graphic_control_label = graphic_control_label,
      block_size = block_size,
      reserved = (packed_fields & 0xe0) >> 5,
      disposal_method = (packed_fields & 0x1c) >> 2,
      user_input_flag = (packed_fields & 0x02) >> 1,
      transparent_color_flag = packed_fields & 0x01,
      delay_time = delay_time,
      transparent_color_index = transparent_color_index
   }, pos + 8
end

local parse_plain_text_extension = function (gif_data_stream, pos)
   local extension_introducer = gif_data_stream:sub(pos, pos)
   local plain_text_label = gif_data_stream:sub(pos + 1, pos + 1)
   local block_size = string.byte(gif_data_stream:sub(pos + 2, pos + 2))
   local text_grid_left_position = string.unpack("<I2", gif_data_stream, pos + 3)
   local text_grid_top_position = string.unpack("<I2", gif_data_stream, pos + 5)
   local text_grid_width = string.unpack("<I2", gif_data_stream, pos + 7)
   local text_grid_height = string.unpack("<I2", gif_data_stream, pos + 9)
   local character_cell_width = string.byte(gif_data_stream:sub(pos + 11, pos + 11))
   local character_cell_height = string.byte(gif_data_stream:sub(pos + 12, pos + 12))
   local text_foreground_color_index = string.byte(gif_data_stream:sub(pos + 13, pos + 13))
   local text_bakcground_color_index = string.byte(gif_data_stream:sub(pos + 14, pos + 14))
   local plain_text_data
   plain_text_data, pos = parse_datasubblocks(gif_data_stream, pos + 15)
   return {
      extension_introducer = extension_introducer,
      plain_text_label = plain_text_label,
      block_size = block_size,
      text_grid_left_position = text_grid_left_position,
      text_grid_top_position = text_grid_top_position,
      text_grid_width = text_grid_width,
      text_grid_height = text_grid_height,
      character_cell_width = character_cell_width,
      character_cell_height = character_cell_height,
      text_foreground_color_index = text_foreground_color_index,
      text_bakcground_color_index = text_bakcground_color_index,
      plain_text_data = plain_text_data
   }, pos
end

local parse_graphic_rendering_block = function (gif_data_stream, pos)
   if gif_data_stream:sub(pos, pos) == "," then
      local table_based_image
      return parse_table_based_image(gif_data_stream, pos)
   elseif gif_data_stream:sub(pos, pos + 1) == "!\x01" then
      local plain_text_extension
      return parse_plain_text_extension(gif_data_stream, pos)
   else
      error(pos .. ": invalid graphic rendering block")
   end
end

local parse_graphic_block = function (gif_data_stream, pos)
   local graphic_control_extension, graphic_rendering_block
   if gif_data_stream:sub(pos, pos + 1) == "!\xf9" then
      graphic_control_extension, pos = parse_graphic_control_extension(gif_data_stream, pos)
   end
   graphic_rendering_block, pos = parse_graphic_rendering_block(gif_data_stream, pos)
   return {
      graphic_control_extension = graphic_control_extension,
      graphic_rendering_block = graphic_rendering_block
   }, pos
end

local parse_comment_extension = function (gif_data_stream, pos)
   local extension_introducer = gif_data_stream:sub(pos, pos)
   local comment_label = gif_data_stream:sub(pos + 1, pos + 1)
   local comment_data
   comment_data, pos = parse_datasubblocks(gif, pos + 2)
   return {
      extension_introducer = extension_introducer,
      comment_label = comment_label,
      comment_data = comment_data
   }, pos
end

local parse_application_extension = function (gif_data_stream, pos)
   local extension_introducer = gif_data_stream:sub(pos, pos)
   local extension_label = gif_data_stream:sub(pos + 1, pos + 1)
   local block_size = string.byte(gif_data_stream:sub(pos + 2, pos + 2))
   local application_identifier = gif_data_stream:sub(pos + 3, pos + 10)
   local application_authentication_code = gif_data_stream:sub(pos + 11, pos + 13)
   local application_data
   application_data, pos = parse_datasubblocks(gif_data_stream, pos + 14)
   return {
      extension_introducer = extension_introducer,
      extension_label = extension_label,
      block_size = block_size,
      application_identifier = application_identifier,
      application_authentication_code = application_authentication_code,
      application_data = application_data
   }, pos
end

local parse_special_purpose_block = function (gif_data_stream, pos)
   local identifier = gif_data_stream:sub(pos, pos + 1)
   if identifier == "!\xff" then
      return parse_application_extension(gif_data_stream, pos)
   elseif identifier == "!\xfe" then
      return parse_comment_extension(gif_data_stream, pos)
   else
      error(pos .. ": invalid special purpose block")
   end
end

local graphic_rendering_block_p = function (gif_data_stream, pos)
   return gif_data_stream:sub(pos, pos) == "," or
      gif_data_stream:sub(pos, pos + 1) == "!\x01"
end

local graphic_block_p = function (gif_data_stream, pos)
   return gif_data_stream:sub(pos, pos + 1) == "!\xf9" or
      graphic_rendering_block_p(gif_data_stream, pos)
end

local special_purpose_block_p = function (gif_data_stream, pos)
   local identifier = gif_data_stream:sub(pos, pos + 1)
   return identifier == "!\xff" or identifier == "!\xfe"
end

local parse_data = function (gif_data_stream, pos)
   if graphic_block_p(gif_data_stream, pos) then
      local graphic_block
      graphic_block, pos = parse_graphic_block(gif_data_stream, pos)
      graphic_block.label = "graphic_block"
      return graphic_block, pos
   elseif special_purpose_block_p(gif_data_stream, pos) then
      local special_purpose_block
      special_purpose_block, pos = parse_special_purpose_block(gif_data_stream, pos)
      special_purpose_block.label = "special_purpose_block"
      return special_purpose_block, pos
   else
      error (pos .. ": invalid data")
   end
end

local parse_data_list = function (gif_data_stream, pos)
   local data_list = {}
   while gif_data_stream:sub(pos, pos) ~= ";" do
      data_list[#data_list + 1], pos = parse_data(gif_data_stream, pos)
   end
   return data_list, pos
end

local parse_trailer = function (gif_data_stream, pos)
   return gif_data_stream:sub(pos, pos), pos + 1
end

local parse_gif = function (gif_data_stream)
   local header, logical_screen, data_list, trailer
   local pos = 1
   header, pos = parse_header(gif_data_stream, pos)
   logical_screen, pos = parse_logical_screen(gif_data_stream, pos)
   data_list, pos = parse_data_list(gif_data_stream, pos)
   trailer, pos = parse_trailer(gif_data_stream, pos)
   return {
      header = header,
      logical_screen = logical_screen,
      data_list = data_list,
      trailer = trailer
   }, pos
end


return parse_gif
