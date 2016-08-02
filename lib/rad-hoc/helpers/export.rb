module RadHoc::Helpers::Export
  def drop_ids(values)
    values.take(@result[:labels].length)
  end
end
