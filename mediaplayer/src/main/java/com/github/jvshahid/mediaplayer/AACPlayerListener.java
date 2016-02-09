package com.github.jvshahid.mediaplayer;

public interface AACPlayerListener {
  void onStart();
  void onError(Exception ex);
  void onStop();
}
