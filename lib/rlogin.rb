require 'socket'

module Net
  # This class implements the BSD Rlogin as it is defined in the RFC 1282.
  class Rlogin
    # The server returns a zero byte to indicate that it has received four
    # null-terminated strings
    RECEIVED_SETTINGS         = 0x00
    
    # The window change control sequence is 12 bytes in length, consisting
    # of a magic cookie (two consecutive bytes of hex FF), followed by two
    # bytes containing lower-case ASCII "s", then 8 bytes containing the
    # 16-bit values for the number of character rows, the number of
    # characters per row, the number of pixels in the X direction, and the
    # number of pixels in the Y direction, in network byte order.  Thus:
    #
    #  FF FF s s rr cc xp yp
    #
    # Other flags than "ss" may be used in future for other in-band control
    # messages.  None are currently defined.
    WINDOW_SIZE_MAGIC_COOKIE  = "\xff\xffss"
    
    # A control byte of hex 02 causes the client to discard all buffered
    # data received from the server that has not yet been written to the
    # client user's screen.
    REQUEST_CLEAR_BUFFER      = 0x02
    
    # A control byte of hex 10 commands the client to switch to "raw"
    # mode, where the START and STOP characters are no longer handled by
    # the client, but are instead treated as plain data.
    REQUEST_SWITCH_TO_RAW     = 0x10
    
    # A control byte of hex 20 commands the client to resume interception
    # and local processing of START and STOP flow control characters.
    REQUEST_SWITCH_TO_NORMAL  = 0x20
    
    # The client responds by sending the current window size as above.
    REQUEST_WINDOW_SIZE       = 0x80
    
    # hostname, dns or ipadress of the remote server
    attr_reader :host
    
    # port of the rlogind daemon on the remote server (DEFAULT: 513)
    attr_reader :port
    
    # username used for login
    attr_reader :username
    
    # password used for login
    attr_reader :password
    
    # the interface to connect from (DEFAULT: 0.0.0.0)
    attr_reader :local_host
    
    # the port to connect from (DEFAULT: 1023)
    attr_reader :local_port
    
    # client user name (DEFAULT: "")
    attr_reader :client_user_name
    
    # server user name (DEFAULT: "")
    attr_reader :server_user_name
    
    # the terminal type (DEFAULT: xterm)
    attr_reader :terminal_type
    
    # the terminal boud rate (DEFAULT: 38400)
    attr_reader :speed
    
    # rows of the emulated terminal (DEFAULT: 24)
    attr_reader :rows
    
    # columns of the emulated terminal (DEFAULT: 80)
    attr_reader :columns
    
    # x pixel of the emulated terminal (DEFAULT: 0)
    attr_reader :pixel_x
    
    # y pixel of the emulated terminal (DEFAULT: 0)
    attr_reader :pixel_y
    
    # the login regex (DEFAULT: /login:\s$/)
    attr_reader :login_token
    
    # the password regex (DEFAULT: /Password:\s$/)
    attr_reader :password_token
    
    # the prompt regex (DEFAULT: /^[^\n]*[#\$]> $/)
    attr_reader :prompt
    
    # the logout regex (DEFAULT: /exit\s+logout$/)
    attr_reader :logout_token
    
    # the logger that will be used for logging messages
    attr_reader :logger
                
    # Creates a new Rlogin client for the passed host and username. Additonal 
    # parameter can be passed as a options hash. If no password is passed,
    # the client will connect without password auth. Options are:
    # :host:: hostname, dns or ipadress of the remote server
    # :port:: port of the rlogind daemon on the remote server (DEFAULT: 513)
    # :username:: username used for login
    # :password:: password used for login
    # :local_host:: the interface to connect from (DEFAULT: 0.0.0.0)
    # :local_port:: the port to connect from (DEFAULT: 1023)
    # :client_user_name:: client user name (DEFAULT: "")
    # :server_user_name:: server user name (DEFAULT: "")
    # :terminal_type:: the terminal type (DEFAULT: xterm)
    # :speed:: the terminal boud rate (DEFAULT: 38400)
    # :rows:: rows of the emulated terminal (DEFAULT: 24)
    # :columns:: columns of the emulated terminal (DEFAULT: 80)
    # :pixel_x:: x pixel of the emulated terminal (DEFAULT: 0)
    # :pixel_y:: y pixel of the emulated terminal (DEFAULT: 0)
    # :login_token:: the login regex (DEFAULT: /login:\s$/)
    # :password_token:: the password regex (DEFAULT: /Password:\s$/)
    # :prompt:: the prompt regex (DEFAULT: /^[^\n]*[#\$]> $/)
    # :logout_token:: the logout regex (DEFAULT: /exit\s+logout$/)
    # :logger:: the logger that will be used for logging messages
    #
    #  Net::Rlogin.new("example.xom", "user", :password => "secret") do |session|
    #    puts session.cmd("ls -al")
    #  end
    def initialize(host, username, options = {}, &block) # :yields: session
      # connection settings
      @host = host
      @port = options[:port] || 513
      @username = username
      @password = options[:password] || nil
      @local_host = options[:local_host] || "0.0.0.0"
      @local_port = options[:local_port] || 1023
      @client_user_name = options[:client_user_name] || ""
      @server_user_name = options[:server_user_name] || ""
      @terminal_type = options[:terminal_type] || "xterm"
      @speed = options[:speed] || 38400
      @rows = options[:rows] || 24
      @columns = options[:columns] || 80
      @pixel_x = options[:pixel_x] || 0
      @pixel_y = options[:pixel_y] || 0
      
      # parser settings
      @login_token = options[:login_token] || /login:\s$/
      @password_token = options[:password_token] || /Password:\s$/
      @prompt = options[:prompt] || /^[^\n]*[#\$]> $/
      @logout_token = options[:logout_token] || /exit\s+logout$/
      
      # logging
      @logger = options[:logger]
      
      # buffer
      @receive_buffer = ""
      @logged_in = false
      
      # start the session if a block is given
      self.session(&block) if block
    end
    
    # openes a session and closes the session after the passed block 
    # has finished
    #
    #  rlogin = Net::Rlogin.new("example.xom", "user", :password => "secret")
    #  rlogin.session do |session|
    #    puts session.cmd("ls -al")
    #  end
    def session(&block) # :yields: session
      @socket = TCPSocket.open(@host, @port, @local_host, @local_port)
      
      # print connection settings and get return code
      @socket.print(connection_settings)
      return_code = @socket.recv(1).unpack("c").first
      
      if return_code == RECEIVED_SETTINGS
        login
        block.call(self)
        logout
      else
        if @logger
          error = @socket.read
          @logger.error("connection couldn't be established: %s" % error)
        end
        @socket.close
      end
    end
    
    # executes the passed command on the remote server and returns the result.
    # return_cmd:: true = show the command that has been send
    # return_prompt:: true = show the returning command prompt
    # terminator:: use a different termiantor (DEFAULT: prompt)
    def cmd(command, return_cmd = false, return_prompt = false, terminator = nil)
      if @logged_in
        prompt = terminator || @prompt
        enter_command(command)
        result = receive_until_token(prompt)
        result.gsub!(/^#{command}\s\s?/, "") unless return_cmd
        result.gsub!(/#{prompt}?/, "") unless return_prompt
        return result
      else
        raise Exception.new("Connection is not initiated (use session)")
      end
    end
    
    # reutrns true if the connection is online false otherwiese
    def logged_in?
      @logged_in
    end
    
    # logout using exit command
    def logout
      if @logged_in
        cmd("exit", true, true, @logout_token)
        handle_logout
      end
    end
        
  private
  
    # parse repsonse and handle the control bytes until the passed token
    # was found in the recieved content
    def receive_until_token(token)
      received = ""
      begin
        byte = @socket.recv(1)
        @receive_buffer << byte
        received << byte
            
        # handle control bytes
        case byte
          when REQUEST_WINDOW_SIZE
            @logger.debug("request: window / screen size") if @logger
            @socket.print(window_size_message)
          when REQUEST_CLEAR_BUFFER
            @logger.debug("request: clear buffer") if @logger
            @receive_buffer = ""
          when REQUEST_SWITCH_TO_RAW
            @logger.debug("request: switch to raw") if @logger
            # ...
          when REQUEST_SWITCH_TO_NORMAL
            @logger.debug("request: switch to normal") if @logger
            # ...
        end
      end while !(@receive_buffer =~ token)
      @logger.debug("received: #{received.inspect}") if @logger
      received
    end
    
    # login using the login credentials
    def login
      receive_until_token(@login_token)
      enter_login unless @logged_in
      if @password # if password was passed, else try without password
        receive_until_token(@password_token)
        enter_password unless @logged_in
      end
      receive_until_token(@prompt)
      @logger.info("logged in") if @logger
    end
  
    # sends the username to the remote server
    def enter_login
      @logger.info("enter login: %s" % @username) if @logger
      enter_command(@username)
    end
  
    # sends the password to the remote server
    def enter_password
      @logger.info("enter password") if @logger
      enter_command(@password)
      @logged_in = true
    end
    
    # sends a string terminated by \n (LF) to the server
    def enter_command(cmd)
      @socket.print("#{cmd}\n")
    end
    
    # handles the logout and clear up session
    def handle_logout
      @logged_in = false
      @receive_buffer = ""
      @socket.close
      @logger.info("logged out") if @logger
    end
  
    # builds the connection setting string that will be send on startup
    def connection_settings
      "\0%s\0%s\0%s/%d\0" % [
        @client_user_name, @server_user_name, @terminal_type, @speed
      ]
    end
  
    # builds the window size string that will be send when the window size
    # magic cookie was found (normaly after connection settings have been send
    # successfully)
    def window_size_message
      WINDOW_SIZE_MAGIC_COOKIE + [@rows, @columns, @pixel_x, @pixel_y].pack("nnnn")
    end
  end
end

