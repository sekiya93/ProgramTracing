def it006(a)
  i = 1
  s = 0
  while i <= 10 do
    if i % 3 == a then
      s = s + 1
    end
    i = i + 1
  end
  p s
end
