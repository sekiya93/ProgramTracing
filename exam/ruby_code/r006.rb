def r006(a, m1, m2, i)
  p a, m1, m2, i
  if i == 1 then
    if a[0] > a[1] then
      return a
    else
      return [a[1], a[0]]
    end
  else
    b = r006(a, m1, m2, i - 1)
    if b[0] > m1 then
      if b[1] > m1 then
        return [b[0], b[1]]
      else
        return [b[0], m1]
      end
    else
      if b[0] > m2 then
        return [m1, b[0]]
      else
        return [m1, m2]
      end
    end
  end
end

def r(a, i)
  if i > 2 then
    if a[i] > a[i - 1] then
      b = r006(a, a[i], a[i - 1], i - 2)
    else
      b = r006(a, a[i - 1], a[i], i - 2)
    end
    return b[1]
  elsif i == 2 then
    b = r006(a, 0, 0, i - 1)
    if b[1] > a[i] then
      return b[1]
    elsif b[0] > a[i] then
      return a[i]
    else
      return b[0]
    end
  elsif i == 1 then
    b = r006(a, 0, 0, i - 1)
    return b[1]
  else
    puts "error"
  end
end
    
