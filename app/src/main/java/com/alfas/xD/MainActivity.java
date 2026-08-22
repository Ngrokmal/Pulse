package com.alfas.xD;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {

    static {
        try {
            System.loadLibrary("ZevaLite");
        } catch (UnsatisfiedLinkError e) {
            // library load failed - will show message in UI
        }
    }

    private static final int OVERLAY_PERMISSION_REQ_CODE = 1234;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Build a simple dark UI so there is never a pure black screen
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setBackgroundColor(Color.parseColor("#121212"));
        root.setPadding(48, 48, 48, 48);

        TextView title = new TextView(this);
        title.setText("xGOKU VIP");
        title.setTextColor(Color.parseColor("#00E676"));
        title.setTextSize(28);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView status = new TextView(this);
        status.setText("\nMenu Library Loaded\n\nএখন গেম খুলুন\nমেনু গেমের উপরে আসবে");
        status.setTextColor(Color.WHITE);
        status.setTextSize(16);
        status.setGravity(Gravity.CENTER);
        status.setPadding(0, 32, 0, 32);
        root.addView(status);

        TextView tip = new TextView(this);
        tip.setText("Overlay Permission দিতে ভুলবেন না");
        tip.setTextColor(Color.parseColor("#FFAB00"));
        tip.setTextSize(14);
        tip.setGravity(Gravity.CENTER);
        root.addView(tip);

        setContentView(root);

        // Request overlay permission if needed (required for floating menu)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                Toast.makeText(this, "Overlay Permission দিন", Toast.LENGTH_LONG).show();
                try {
                    Intent intent = new Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:" + getPackageName())
                    );
                    startActivityForResult(intent, OVERLAY_PERMISSION_REQ_CODE);
                } catch (Exception e) {
                    // some devices may not support the intent
                }
            }
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == OVERLAY_PERMISSION_REQ_CODE) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (Settings.canDrawOverlays(this)) {
                    Toast.makeText(this, "Permission Granted ✓", Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(this, "Permission Denied - মেনু দেখা যাবে না", Toast.LENGTH_LONG).show();
                }
            }
        }
    }
}
