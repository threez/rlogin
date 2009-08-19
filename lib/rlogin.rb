require 'socket'

module Net
  # This class implements the BSD Rlogin as it is defined in the RFC 1282.
  class Rlogin
    RECEIVED_SETTINGS         = 0x00
    WINDOW_SIZE_MAGIC_COOKIE  = "\xff\xffss"
    REQUEST_CLEAR_BUFFER      = 0x02
    REQUEST_SWITCH_TO_RAW     = 0x10
    REQUEST_SWITCH_TO_NORMAL  = 0x20
    REQUEST_WINDOW_SIZE       = 0x80
    
    attr_reader :host, :port, :username, :password, :local_host, :local_port,
                :client_user_name, :server_user_name, :terminal_type, :speed,
                :rows, :columns, :pixel_x, :pixel_y, :login_token, 
                :password_token, :prompt, :logout_token, :logger
                
    # Creates a new Rlogin client for the passed host and username. Additonal 
    # parameter can be passed as a options hash. Options are:
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

