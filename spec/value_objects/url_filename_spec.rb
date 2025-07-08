# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UrlFilename do
  describe '.from_url' do
    it 'creates UrlFilename from URL' do
      url_filename = described_class.from_url('https://example.com/image.jpg')
      expect(url_filename.url).to eq('https://example.com/image.jpg')
      expect(url_filename.filename).to eq('image')
      expect(url_filename.extension).to eq('jpg')
    end
  end

  describe '#initialize' do
    it 'strips whitespace from URL' do
      url_filename = described_class.new('  https://example.com/file.png  ')
      expect(url_filename.url).to eq('https://example.com/file.png')
    end

    it 'handles nil URL' do
      url_filename = described_class.new(nil)
      expect(url_filename.url).to eq('')
      expect(url_filename.filename).to eq('download')
    end
  end

  describe '#full_filename' do
    it 'returns filename with extension' do
      url_filename = described_class.new('https://example.com/document.pdf')
      expect(url_filename.full_filename).to eq('document.pdf')
    end

    it 'returns filename without extension when no extension' do
      url_filename = described_class.new('https://example.com/document')
      expect(url_filename.full_filename).to eq('document')
    end

    it 'returns default filename for invalid URLs' do
      url_filename = described_class.new('invalid-url')
      expect(url_filename.full_filename).to eq('download')
    end
  end

  describe '#valid?' do
    it 'returns true for valid extracted filename' do
      url_filename = described_class.new('https://example.com/image.jpg')
      expect(url_filename).to be_valid
    end

    it 'returns false for default filename' do
      url_filename = described_class.new('https://example.com/')
      expect(url_filename).not_to be_valid
    end

    it 'returns false for invalid URLs' do
      url_filename = described_class.new('not-a-url')
      expect(url_filename).not_to be_valid
    end
  end

  describe '#valid_url?' do
    it 'returns true for HTTP URLs' do
      url_filename = described_class.new('http://example.com/file.txt')
      expect(url_filename).to be_valid_url
    end

    it 'returns true for HTTPS URLs' do
      url_filename = described_class.new('https://example.com/file.txt')
      expect(url_filename).to be_valid_url
    end

    it 'returns false for invalid URLs' do
      url_filename = described_class.new('ftp://example.com/file.txt')
      expect(url_filename).not_to be_valid_url
    end

    it 'returns false for empty URLs' do
      url_filename = described_class.new('')
      expect(url_filename).not_to be_valid_url
    end
  end

  describe '#to_s' do
    it 'returns full filename' do
      url_filename = described_class.new('https://example.com/file.txt')
      expect(url_filename.to_s).to eq('file.txt')
    end
  end

  describe '#==' do
    it 'returns true for same URL' do
      url_filename1 = described_class.new('https://example.com/file.txt')
      url_filename2 = described_class.new('https://example.com/file.txt')
      expect(url_filename1).to eq(url_filename2)
    end

    it 'returns false for different URLs' do
      url_filename1 = described_class.new('https://example.com/file1.txt')
      url_filename2 = described_class.new('https://example.com/file2.txt')
      expect(url_filename1).not_to eq(url_filename2)
    end

    it 'returns false for objects of other classes' do
      url_filename = described_class.new('https://example.com/file.txt')
      expect(url_filename).not_to eq('https://example.com/file.txt')
    end
  end

  describe 'filename extraction' do
    it 'extracts simple filename' do
      url_filename = described_class.new('https://example.com/image.jpg')
      expect(url_filename.filename).to eq('image')
      expect(url_filename.extension).to eq('jpg')
    end

    it 'extracts filename from nested path' do
      url_filename = described_class.new('https://example.com/path/to/file.png')
      expect(url_filename.filename).to eq('file')
      expect(url_filename.extension).to eq('png')
    end

    it 'handles filename with multiple dots' do
      url_filename = described_class.new('https://example.com/file.min.js')
      expect(url_filename.filename).to eq('file.min')
      expect(url_filename.extension).to eq('js')
    end

    it 'handles filename without extension' do
      url_filename = described_class.new('https://example.com/README')
      expect(url_filename.filename).to eq('README')
      expect(url_filename.extension).to be_nil
    end

    it 'removes query parameters' do
      url_filename = described_class.new('https://example.com/file.jpg?v=123&size=large')
      expect(url_filename.filename).to eq('file')
      expect(url_filename.extension).to eq('jpg')
    end

    it 'sanitizes dangerous characters' do
      url_filename = described_class.new('https://example.com/file<script>.txt')
      expect(url_filename.filename).to eq('download')
      expect(url_filename.extension).to be_nil
    end

    it 'collapses multiple underscores' do
      url_filename = described_class.new('https://example.com/file___name.txt')
      expect(url_filename.filename).to eq('file_name')
      expect(url_filename.extension).to eq('txt')
    end

    it 'uses default filename for root path' do
      url_filename = described_class.new('https://example.com/')
      expect(url_filename.filename).to eq('download')
      expect(url_filename.extension).to be_nil
    end

    it 'uses default filename for empty path' do
      url_filename = described_class.new('https://example.com')
      expect(url_filename.filename).to eq('download')
      expect(url_filename.extension).to be_nil
    end
  end

  describe 'filename length limits' do
    it 'truncates very long filenames' do
      long_filename = 'a' * 300
      url_filename = described_class.new("https://example.com/#{long_filename}.txt")
      expect(url_filename.filename.length).to be <= 251 # 255 - 4 (".txt")
    end

    it 'handles long filename without extension' do
      long_filename = 'a' * 300
      url_filename = described_class.new("https://example.com/#{long_filename}")
      expect(url_filename.filename.length).to be <= 255
    end
  end

  describe 'immutability' do
    it 'is immutable' do
      url_filename = described_class.new('https://example.com/file.txt')
      expect(url_filename).to be_frozen
    end
  end
end
