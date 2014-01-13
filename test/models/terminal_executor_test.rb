require_relative '../test_helper'

describe TerminalExecutor do
  let(:output) { [] }
  subject { TerminalExecutor.new(output) }

  describe 'output' do
    before do
      subject.execute!('echo "hi"', 'echo "hello"')
    end

    it 'keeps all lines' do
      output.join.must_equal("hi\r\nhello\r\n")
    end
  end

  describe 'stderr' do
    before do
      subject.execute!('echo "hi" >&2', 'echo "hello" >&2')
    end

    it 'keeps all lines' do
      output.join.must_equal("hi\r\nhello\r\n")
    end
  end

  describe 'command failures' do
    before do
      subject.execute!('ls /nonexistent/place', 'echo "hi"')
    end

    it 'does not execute the other commands' do
      output.join.must_equal([
        "ls: cannot access /nonexistent/place: No such file or directory\r\n",
        "Failed to execute \"ls /nonexistent/place\"\r\n"
      ].join)
    end
  end

  describe '#stop!' do
    it 'properly kills the execution' do
      thr = Thread.new(subject) do |shell|
        sleep(0.1) until shell.pid
        shell.stop!
      end

      Timeout.timeout(5) do
        subject.execute!('sleep 100').must_equal(false)
      end

      thr.join
    end
  end

  it 'correctly returns error value' do
    subject.execute!('blah').must_equal(false)
  end

  it 'correctly returns success value' do
    subject.execute!('echo "hi"').must_equal(true)
  end
end
