package com.github.jvshahid.mediaplayer;

public class DecodingInfo {
  public final short[] decodedData;
  public final int consumedData;

  public DecodingInfo(int consumedData, short[] decodedData) {
    this.consumedData = consumedData;
    this.decodedData = decodedData;
  }
}
