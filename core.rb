# core.rb Core War simulator in Ruby
# Author: Eric Lang
# For more info: http://www.exyzzy.com

class Mars
  # initialize sets up the data structures and the procedures for each opcode (type)
  def initialize
    @ip = [0,0]             # Instruction pointers
    @cycle = 0              # Current cycle number

    #Abort messages
    @msg = ["No Message",   # 0
         "Illegal Mode",    # 1
         "Draw, No Winner", # 2
         "DAT Executed",    # 3
         "??"]              # 4
    @msgIndex = 0           # Abort code
    @msgPlayer = -1         # Player who generated the abort code

                            # Core memory array, element layout:  
                            #   [Type, ModeA, A, ModeB, B, Occupier]
    @core = []              # Core memory
                            
    @TYPE     = 0           # Array positions in a core element
    @MODEA    = 1
    @FIELDA   = 2
    @MODEB    = 3
    @FIELDB   = 4
    @OCCUPIER = 5    
    
                            # For disassembly printout
    @modes = ["\#", "\$", "\@"]
                            # For core map printout
    @players = ["A", "B"]
    
    @MAX_CYCLE = 80000      # Max cycles before a draw
    @MAX_CORE = 8000        # Max size of the memory core

    @IMMEDIATE = 0          # Mode Codes
    @RELATIVE = 1
    @INDIRECT = 2
                            # Operations [mnemonic, proc] (proc added below)
    @ops = [["DAT"],        # 0
            ["MOV"],        # 1
            ["ADD"],        # 2
            ["SUB"],        # 3
            ["JMP"],        # 4
            ["JMZ"],        # 5
            ["DJZ"],        # 6
            ["CMP"]]        # 7

                            # Add procs to ops: 
    @ops[0] << lambda do |p, a, b|            # DAT proc
      @msgIndex = 3                           # DAT executed (Error)
      @msgPlayer = p                          # Losing player is p
      false                                   # Return false for abort
    end #lambda DAT
    
    @ops[1] << lambda do |p, a, b|            # MOV proc
      if @core[@ip[p]][@MODEA] == @IMMEDIATE
        @core[b][@FIELDB] = @core[a][@FIELDA]
      elsif @core[@ip[p]][@MODEB] == @IMMEDIATE
        @core[b][@FIELDB] = @core[a][@FIELDB]
      else
        @core[b] = @core[a]        
      end
      @core[b][@OCCUPIER] = p
      @ip[p] = (@ip[p] + 1) % @MAX_CORE
      true
    end #lambda MOV

    @ops[2] << lambda do |p, a, b|            # ADD proc
      if @core[@ip[p]][@MODEA] == @IMMEDIATE
        @core[b][@FIELDB] = @core[a][@FIELDA] + @core[b][@FIELDB]
      else
        @core[b][@FIELDB] = @core[a][@FIELDB] + @core[b][@FIELDB]
      end
      @core[b][@OCCUPIER] = p
      @ip[p] = (@ip[p] + 1) % @MAX_CORE
      true
    end #lambda ADD
    
    @ops[3] << lambda do |p, a, b|            # SUB proc
      if @core[@ip[p]][@MODEA] == @IMMEDIATE
        @core[b][@FIELDB] = @core[b][@FIELDB] - @core[a][@FIELDA]
      else
        @core[b][@FIELDB] = @core[b][@FIELDB] - @core[a][@FIELDB]
      end
      @core[b][@OCCUPIER] = p
      @ip[p] = (@ip[p] + 1) % @MAX_CORE
      true
    end #lambda SUB

    @ops[4] << lambda do |p, a, b|            # JMP proc
      if @core[@ip[p]][@MODEA] == @RELATIVE || @core[@ip[p]][@MODEA] == @INDIRECT
        @ip[p] = a                            #addreses have been calculated in runGame
      else
        @ip[p] = (@ip[p] + @core[a][@FIELDA]) % @MAX_CORE # Immediate is same as relative 
      end
      # puts "  JMP to: #{@ip[p]} p,a,b: #{p}, #{a}, #{b}"
      true
    end #lambda JMP

    @ops[5] << lambda do |p, a, b|            # JMZ proc
      if @core[b][@FIELDB] == 0
        @ops[4][1].call(p, a, b)              # call JMP
      else
        @ip[p] = (@ip[p] + 1) % @MAX_CORE
      end
      true     
    end #lambda JMZ

    @ops[6] << lambda do |p, a, b|            # DJZ proc
      @core[b][@FIELDB] = @core[b][@FIELDB] - 1
      @core[b][@OCCUPIER] = p
      @ops[5][1].call(p, a, b)                # call JMZ      
      true
    end #lambda DJZ

    @ops[7] << lambda do |p, a, b|            # CMP proc
       if (@core[@ip[p]][@MODEA] != @IMMEDIATE) && 
          (@core[@ip[p]][@MODEB] == @IMMEDIATE)
         if @core[a][@FIELDB] != @core[b][@FIELDB]
           @ip[p] = (@ip[p] + 2) % @MAX_CORE
         else
           @ip[p] = (@ip[p] + 1) % @MAX_CORE
         end
      elsif (@core[@ip[p]][@MODEA] == @IMMEDIATE)
        if @core[a][@FIELDA] != @core[b][@FIELDB]
          @ip[p] = (@ip[p] + 2) % @MAX_CORE
        else
          @ip[p] = (@ip[p] + 1) % @MAX_CORE
        end
      else # compare both fields
        if (@core[a][@FIELDA] != @core[b][@FIELDA]) || 
           (@core[a][@FIELDB] != @core[b][@FIELDB])
          @ip[p] = (@ip[p] + 2) % @MAX_CORE
        else
          @ip[p] = (@ip[p] + 1) % @MAX_CORE
        end        
      end
      true
    end #lambda CMP

    i = 0;                                    # Zero the core
    while i < @MAX_CORE
      @core[i] = [0,0,0,0,0,-1]               # -1 in Occupier for unused
      i += 1
    end
  end #initialize    

  # runGame is the simulation loop            # @core[Type, ModeA, A, ModeB, B, Occupier]
  def runGame
    addr = [0, 0]                             # ip address of operand (A & B)
    keepRunning = true
    while keepRunning do
      lineStr = ""
      @ip.each_index do |player|              # For each player (1 & 2)
                                              # Print a split screen disassembly of each instruction executed 
        if player == 0
          lineStr = "\[#{@ip[player]}\]: " + @ops[@core[@ip[player]][0]][0] + 
          ", " + @modes[@core[@ip[player]][1]] + "#{@core[@ip[player]][2]}, " + 
          @modes[@core[@ip[player]][3]] + "#{@core[@ip[player]][4]}"
        else
          lineStr = lineStr + ' ' * (40 - lineStr.length) + "\[#{@ip[player]}\]: " + 
          @ops[@core[@ip[player]][0]][0] + ", " + @modes[@core[@ip[player]][1]] + 
          "#{@core[@ip[player]][2]}, " + @modes[@core[@ip[player]][3]] + "#{@core[@ip[player]][4]}"
          puts(lineStr)
        end
        addr.each_index do |field|            # For each field (A & B)  
          case @core[@ip[player]][@MODEA+(field * 2)] #Process the mode
            when @IMMEDIATE                   # Immediate mode
              addr[field] = @ip[player]       # Point to current instruction
            when @RELATIVE                    # Relative mode
              addr[field] = (@ip[player] + @core[@ip[player]][@FIELDA + (field * 2)]) % @MAX_CORE
            when @INDIRECT                    # Indirect mode
              ind = (@ip[player] + @core[@ip[player]][@FIELDA + (field * 2)]) % @MAX_CORE
              addr[field] = (ind + @core[ind][@FIELDB]) % @MAX_CORE
            else
              keepRunning = false
              @msgIndex = 1                   # Illegal mode
              @msgPlayer = player
          end #case
        end #@addr...
        if !@ops[@core[ @ip[player] ][@TYPE] ][1].call(player, addr[0], addr[1]) #call the operation
          keepRunning = false
        end #if..
        
      end #@ip...
      @cycle += 1
      if @cycle == @MAX_CYCLE
        @msgIndex = 2                         # Draw
        keepRunning = false
      end #if..
    end #while...

    puts "Core Map:"                          # Draw an 80 X 100 map of the core
    line = 0
    lineStr = "%5d" % 0.to_s + ":"
    
    @core.each_index do |i|
      if @core[i][@OCCUPIER] == 0
        lineStr += "A"
      elsif @core[i][@OCCUPIER] == 1
        lineStr += "B"
      else
        lineStr += "_"
      end
      line += 1
      
      if line >= 80
        puts(lineStr)
        line = 0
        lineStr = "%5d" % (i + 1).to_s + ":"        
      end
    end #@core.each_index

    puts "Done: " + @msg[@msgIndex]           # Final stats
    if (@msgIndex == 1) || (@msgIndex == 3)
      puts "Loser: " + @players[@msgPlayer]
    end
    puts "IP: A@#{@ip[0]}, B@#{@ip[1]}"    
    puts "Cycle: #{@cycle}" 
    
  end #runGame

  # parseFile reads the assemby (redcode) file and assembles it into a buffer with the same structure as core
  # it uses regexp to look for tokens. It handles comments preceded by ; and is case insensitive
  # all 3 letter opcodes are handled and one or two operands preceded by a mode: #$@ or nothing (interpreted as $)
  # positive and negative integer operands are permitted
  
  def parseFile(player, fName)
    typetoi = { "DAT" => 0, "MOV" => 1, "ADD" => 2, "SUB" => 3, "JMP" => 4, "JMZ" => 5, "DJZ" => 6, "CMP" => 7}
    modetoi = { "\#" => 0, "\$" => 1, "\@" => 2}
    bufCore = []                              # Holds the compiled programs for each player
    f = File.open(fName, "r")                 # Open fName for reading
    puts "Parsing file: " + fName
    f.each_line do |line|  
      puts line
      line.slice!(/;.*/)                      # Delete comments
      line1 = line.upcase
      typeIndex = /[A-Z][A-Z][A-Z]/ =~ line1  # Get Type
      if typeIndex != nil                     # Type exists
        type = $~[0]
        puts "  Type: " + type
        line1 = $~.post_match                 # Trim out the type
        numIndex = /[\-|\+|\d]\d*/ =~ line1   # Get First Field
        
        if numIndex == nil
            puts "Error, no Fields"
        else
          fieldA = $~[0].to_i
        end #numIndex...
        
        line1 = $~.pre_match                  # Before the first field
        line2 = $~.post_match                 # After the first field
        
        modeIndex = /[\#\$\@]/ =~ line1       # Get Mode for first field
        
        if modeIndex == nil
          modeA = "$"
        else
          modeA = $~[0]
        end # if modeIndex
        puts "  ModeA: " + modeA              # Print the assembled instruction
        puts "  FieldA: #{fieldA}"

        numIndex = /[\-|\+|\d]\d*/ =~ line2   # Get Second Field
        
        if numIndex == nil
          fieldB = fieldA                     # Copy first field & mode if no second
          modeB = modeA
        else
          fieldB = $~[0].to_i

          line1 = $~.pre_match                # Before the second field

          modeIndex = /[\#\$\@]/ =~ line1     # Get Mode for second field
          if modeIndex == nil
            modeB = "$"
          else
            modeB = $~[0]
          end
        end # if numIndex...
        
        puts "  ModeB: " + modeB
        puts "  FieldB: #{fieldB}"
        puts "  Opcode: #{typetoi[type]}, #{modetoi[modeA]}, #{fieldA}, #{modetoi[modeB]}, #{fieldB}"
        bufCore << [typetoi[type], modetoi[modeA], fieldA, modetoi[modeB], fieldB, player]
      end #if typeIndex...
      # Instruction Regexp: /[A-Za-z]+|[#$@]|[[-|+]\d+]/      
      # Comment Regexp: /;.*/      
    end #each_line
    f.close
    puts "Core Dump, player[#{player}]:"      # Write out the compiled program
    bufCore.each do |element|                 
      puts "  #{element[0]}, #{element[1]}, #{element[2]}, #{element[3]}, #{element[4]}"
    end #bufCore.each
    puts
    bufCore
  end #parseFile

  # loadPrograms loads the assembled programs from the temp buffers into core at random locations
  def loadPrograms(playerCore)
    @ip[0] = rand(@MAX_CORE)                  # Randomly place the programs in core
    @ip[1] = (rand(@MAX_CORE - @ip[0].size) + @ip[0] + @ip[0].size) % @MAX_CORE
    @ip.each_index do |player|                # Copy each program into core
      puts("Player #{player} loaded at: #{@ip[player]}  size:#{playerCore[player].size}")
      ci = @ip[player]
      playerCore[player].each_index do |bi|
        @core[ci] = playerCore[player][bi]
        ci += 1
      end # @ip[player]..
    end # @ip.each_index ..
  end # loadPrograms...

end #Mars    

def play (mars, file1, file2)
  playerCore = []
  playerCore[0] = mars.parseFile(0, file1)    # Assemble player A
  playerCore[1] = mars.parseFile(1, file2)    # Assemble player B
  mars.loadPrograms(playerCore)               # Load the programs into core
  mars.runGame                                # Run them
end #play 
    
mars = Mars.new
play(mars, ARGV[0], ARGV[1])                  #From command line: ruby core.rb fname1.dat fname2.dat
