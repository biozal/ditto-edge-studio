// EdgeStudio/Controls/AnimatedNodeState.cs
using EdgeStudio.Shared.Services;
using System;

namespace EdgeStudio.Controls;

public enum AnimationPhase
{
    Appearing,
    Visible,
    Disappearing,
    Gone
}

/// <summary>
/// Per-node animation state. Tracks current and target position, opacity, scale.
/// Call Tick(dt) each frame to interpolate toward targets using exponential easing.
/// </summary>
public class AnimatedNodeState
{
    private const float LerpSpeed = 8f;
    private const float ConvergenceThreshold = 0.5f;
    private const float OpacityThreshold = 0.01f;

    public string PeerKey { get; }
    public AnimationPhase Phase { get; private set; }

    public float CurrentX { get; private set; }
    public float CurrentY { get; private set; }
    public float Opacity { get; private set; }
    public float Scale { get; private set; }

    public float TargetX { get; private set; }
    public float TargetY { get; private set; }
    private float _targetOpacity;
    private float _targetScale;

    public bool IsAnimating
    {
        get
        {
            if (Phase == AnimationPhase.Gone) return false;
            return MathF.Abs(CurrentX - TargetX) > ConvergenceThreshold
                || MathF.Abs(CurrentY - TargetY) > ConvergenceThreshold
                || MathF.Abs(Opacity - _targetOpacity) > OpacityThreshold
                || MathF.Abs(Scale - _targetScale) > OpacityThreshold;
        }
    }

    private AnimatedNodeState(string peerKey)
    {
        PeerKey = peerKey;
    }

    public static AnimatedNodeState CreateAppearing(string peerKey, NodePosition targetPosition)
    {
        return new AnimatedNodeState(peerKey)
        {
            Phase = AnimationPhase.Appearing,
            CurrentX = 0, CurrentY = 0,
            Opacity = 0f, Scale = 0.5f,
            TargetX = (float)targetPosition.X,
            TargetY = (float)targetPosition.Y,
            _targetOpacity = 1f, _targetScale = 1f
        };
    }

    public static AnimatedNodeState CreateVisible(string peerKey, NodePosition position)
    {
        return new AnimatedNodeState(peerKey)
        {
            Phase = AnimationPhase.Visible,
            CurrentX = (float)position.X,
            CurrentY = (float)position.Y,
            Opacity = 1f, Scale = 1f,
            TargetX = (float)position.X,
            TargetY = (float)position.Y,
            _targetOpacity = 1f, _targetScale = 1f
        };
    }

    public void SetTarget(NodePosition newTarget)
    {
        TargetX = (float)newTarget.X;
        TargetY = (float)newTarget.Y;
    }

    public void BeginDisappearing()
    {
        Phase = AnimationPhase.Disappearing;
        TargetX = 0;
        TargetY = 0;
        _targetOpacity = 0f;
        _targetScale = 0.5f;
    }

    public void Tick(float deltaTime)
    {
        if (Phase == AnimationPhase.Gone) return;

        var t = 1f - MathF.Exp(-LerpSpeed * deltaTime);

        CurrentX += (TargetX - CurrentX) * t;
        CurrentY += (TargetY - CurrentY) * t;
        Opacity += (_targetOpacity - Opacity) * t;
        Scale += (_targetScale - Scale) * t;

        if (!IsAnimating)
        {
            CurrentX = TargetX;
            CurrentY = TargetY;
            Opacity = _targetOpacity;
            Scale = _targetScale;

            if (Phase == AnimationPhase.Appearing)
                Phase = AnimationPhase.Visible;
            else if (Phase == AnimationPhase.Disappearing)
                Phase = AnimationPhase.Gone;
        }
    }
}
