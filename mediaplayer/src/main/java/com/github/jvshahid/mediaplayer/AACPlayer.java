package com.github.jvshahid.mediaplayer;

import java.io.IOException;
import java.io.InputStream;
import java.nio.channels.SocketChannel;
import java.util.HashMap;
import java.util.Map;

import org.apache.http.HttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.DefaultHttpClient;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.util.Log;

/**
 * MediaPlayer
 */
public class AACPlayer {
  static {
    System.loadLibrary("ffmpeg");
    System.loadLibrary("media-jni");
  }

  private static final int AAC_BUFFER_SIZE = 1024 * 10; // 10K buffer

  private AudioTrack track;
  private int bufferSize;
  private final String url;
  private volatile boolean shouldStop = false;

  // pointer to native data structure
  private long ptr;

  private Thread t;

  private AACPlayerListener listener;

  private final int timeout;
  private SocketChannel channel;
  private byte[] buffer;
  private int bufferLength;
  private InputStream responseInputStream;
  private HttpGet request;

  public AACPlayer(String url) { this(url, 5000); }

  public AACPlayer(String url, int timeout) {
    this.url = url;
    this.timeout = timeout;
  }

  public void play() {
    if(shouldStop) {
      throw new UnsupportedOperationException("Cannot restart player, please instantiate a new instace");
    }

    if(listener != null) {
      listener.onStart();
    }

    Log.i(getClass().getName(), "Inside AACPlayer::play()");
    t = new Thread(new Runnable() {
      @Override
      public void run() {
        try {
          init();
          playImpl();
        } catch(Exception e) {
          if(!shouldStop) {
            if(listener != null) {
              listener.onError(e);
            }
            Map<String, String> eventParams = new HashMap<String, String>();
            eventParams.put("error", e.getMessage());
            Log.e(getClass().getName(), "Something bad happened", e);
          }
        }
      }
    });
    t.setName("Stream decoding thread");
    t.start();
  }

  public void setListener(AACPlayerListener listener) { this.listener = listener; }

  /**
   * Returns true if the track is playing, false otherwise
   *
   * @return
   */
  public boolean isPlaying() { return !shouldStop; }

  /**
   * Stop playback
   */
  public void stop() {
    Log.i(getClass().getName(), "Inside AACPlayer::stop()");

    if(shouldStop) {
      return;
    }

    Log.i(getClass().getName(), "Inside AACPlayer::stop(), actually stopping");

    shouldStop = true;

    t.interrupt();

    if(request != null) {
      request.abort();
    }

    synchronized(this) {
      if(listener != null) {
        listener.onStop();
      }

      if(track != null) {
        track.stop();
        track.release();
        track = null;
      }
      try {
        if(channel != null) {
          channel.close();
        }
      } catch(Exception e) {
        Log.w(getClass().getName(), "Cannot close http connection to " + url, e);
      }
      t = null;
      releaseNative(this);
    }
  }

  /**
   * see {@link AudioTrack#setStereoVolume(float, float)}
   */
  public void setVolume(float left, float right) {
    if(track != null) {
      track.setStereoVolume(left, right);
    }
  }

  private void playImpl() throws IOException {
    bufferLength = 0;
    while(true) {
      synchronized(this) {
        if(shouldStop) {
          return;
        }
        int read = readChunk();
        if(read == -1) {
          stop();
          return;
        }
        DecodingInfo decodingInfo = decodeNative(this, buffer, bufferLength);
        bufferLength -= decodingInfo.consumedData;
        System.arraycopy(buffer, decodingInfo.consumedData, buffer, 0, bufferLength);
        track.write(decodingInfo.decodedData, 0, decodingInfo.decodedData.length);
      }
    }
  }

  @Override
  public void finalize() {
    stop();
  }

  private synchronized void connect() throws IOException {
    // create the buffers
    this.buffer = new byte[AAC_BUFFER_SIZE];

    DefaultHttpClient client = new DefaultHttpClient();
    Log.i(getClass().getName(), "Openning a connection to: " + url);
    request = new HttpGet(url);
    HttpResponse response = client.execute(request);
    if(response.getStatusLine().getStatusCode() != 200) {
      throw new IOException("Received " + response.getStatusLine().getStatusCode() + " status code");
    }
    responseInputStream = response.getEntity().getContent();
  }

  private int readChunk() throws IOException {
    int count = 0;
    while(buffer.length - bufferLength > 0) {
      int read = responseInputStream.read(buffer, bufferLength, buffer.length - bufferLength);
      if(read <= 0) {
        return count;
      }
      count += read;
      bufferLength += read;
    }
    return count;
  }

  private synchronized void init() throws IOException {
    if(shouldStop)
      return;

    connect();
    int read = readChunk();
    if(read <= 0) {
      throw new IOException("Cannot get data from streaming server at " + url);
    }
    AACInfo info = initNative(this, buffer, bufferLength);

    // trying smaller buffer scalers starting at 200 and ending with 10
    for(int bufferSizeFactor = 200; bufferSizeFactor >= 10; bufferSizeFactor /= 2) {
      Log.i(getClass().getName(), "Sample rate: " + info.sampleRate + ", channels: " + info.channels);
      int outputFormat = info.channels == 1 ? AudioFormat.CHANNEL_OUT_MONO : AudioFormat.CHANNEL_OUT_STEREO;
      int encoding = AudioFormat.ENCODING_PCM_16BIT;
      Log.i(getClass().getName(), "Using buffer size " + bufferSize);
      bufferSize = AudioTrack.getMinBufferSize(info.sampleRate, outputFormat, encoding) * bufferSizeFactor;
      track = new AudioTrack(AudioManager.STREAM_MUSIC, info.sampleRate, outputFormat, encoding, bufferSize,
                             AudioTrack.MODE_STREAM);
      if(track.getState() == AudioTrack.STATE_INITIALIZED) {
        // if the audio tracker was initialized successfully then
        // start playing and return
        track.play();
        return;
      }
    }
    listener.onError(new Exception("Cannot initialize audio track"));
    track = null;
    return;
  }

  // the following are all static and synchronized to make sure that we never
  // use ffmpeg
  // from more than one thread
  private static synchronized native AACInfo initNative(AACPlayer player, byte[] buffer, int length);

  private static synchronized native DecodingInfo decodeNative(AACPlayer player, byte[] buffer, int length);

  private static synchronized native void releaseNative(AACPlayer player);
}
