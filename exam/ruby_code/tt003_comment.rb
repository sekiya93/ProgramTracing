def tt003(tape)
  pos   = 3
  state = 0
  while state != 'h' do
    p tape
    puts 'pos:' + pos.to_s + ', state:' + state.to_s
    if state == 0 then
      if tape[pos] == '' then
        tape[pos] = 1
        pos = pos + 1
        state = 1
      elsif tape[pos] == 0 then
        tape[pos] = 1
        pos = pos + 1
        state = 1
      else
        tape[pos] = 0
        pos = pos - 1
        state = 0
      end
    else
      if tape[pos] == '' then
        pos = pos - 1
        state = 'h'
      elsif tape[pos] == 0 then
        pos = pos + 1
        state = 1
      else 
        pos = pos + 1
      end
    end
  end
    p tape
    puts 'pos:' + pos.to_s + ', state:' + state.to_s
end

tape = ['','',0,0,'']

tt003(tape)
puts
tt003(tape)
puts
tt003(tape)
puts
tt003(tape)
